# setup-search-pipeline.ps1
# Deploys the Azure AI Search pipeline (data source, index, skillset, indexer)
# using Foundry-aligned patterns: keyless billing (AIServicesByIdentity), managed identity auth,
# Content Understanding skill (extraction + built-in chunking), ChatCompletion (GenAI Prompt) skill (Preview),
# and Azure AI Foundry Embedding skill.
#
# Prerequisites:
#   1. Run 'azd up' first to deploy infrastructure.
#   2. Run 'azd env get-values' to confirm environment values are available.
#   3. RBAC roles must be propagated (may take a few minutes after deployment).
#
# API version: 2025-11-01-Preview
#   - ContentUnderstandingSkill                         ➜ 2025-11-01-Preview and later
#   - TextSplit token-based chunking (azureOpenAITokens)   ➜ 2024-09-01-preview and later
#   - ChatCompletionSkill (GenAI Prompt)                   ➜ public preview
#   - AIServicesByIdentity keyless billing                 ➜ public preview

param(
    [string]$IndexName = "pdf-index",
    [string]$BlobContainer = "pdfs",
    [string]$ImageContainer = "pdf-images",
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$apiVersion = "2025-11-01-Preview"

# ── Helpers ──────────────────────────────────────────────────────────────────

function Get-AzdValue([string]$key) {
    $val = azd env get-value $key 2>$null
    if (-not $val) { throw "Missing azd env value: $key. Run 'azd up' first." }
    return $val.Trim()
}

function Get-SearchToken {
    $token = az account get-access-token --resource https://search.azure.com/ --query accessToken -o tsv 2>$null
    if (-not $token) { throw "Failed to get search access token. Run 'az login' first." }
    return $token
}

function Invoke-SearchApi {
    param(
        [string]$Endpoint,
        [string]$Path,
        [string]$Token,
        [string]$Body,
        [string]$Method = "PUT"
    )
    $uri = "${Endpoint}${Path}?api-version=${apiVersion}"
    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
    }
    try {
        $response = Invoke-RestMethod -Uri $uri -Method $Method -Headers $headers -Body $Body
        return $response
    }
    catch {
        $status = $_.Exception.Response.StatusCode.value__
        $detail = $_.ErrorDetails.Message
        throw "Search API call failed (HTTP $status): $detail"
    }
}

# ── Load environment values ──────────────────────────────────────────────────

Write-Host "Loading environment values from azd..." -ForegroundColor Yellow

$searchEndpoint    = Get-AzdValue "SEARCH_ENDPOINT"
$subscriptionId    = Get-AzdValue "AZURE_SUBSCRIPTION_ID"
$resourceGroup     = Get-AzdValue "AZURE_RESOURCE_GROUP_NAME"
$storageAccount    = Get-AzdValue "STORAGE_ACCOUNT_NAME"
$aiFoundryEndpoint = Get-AzdValue "AI_FOUNDRY_ENDPOINT"
$aiServicesEndpoint = Get-AzdValue "AI_FOUNDRY_SUBDOMAIN_URL"

# Fallback: if subdomain URL not available, construct from services endpoint
if (-not $aiServicesEndpoint -or $aiServicesEndpoint -eq "") {
    $aiServicesEndpoint = Get-AzdValue "AI_FOUNDRY_ENDPOINT"
}

$storageResourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Storage/storageAccounts/$storageAccount"

Write-Host "  Search Endpoint:    $searchEndpoint" -ForegroundColor Cyan
Write-Host "  Storage Account:    $storageAccount" -ForegroundColor Cyan
Write-Host "  AI Foundry Endpoint: $aiFoundryEndpoint" -ForegroundColor Cyan
Write-Host "  AI Foundry URL:      $aiServicesEndpoint" -ForegroundColor Cyan
Write-Host ""

# ── Get bearer token ────────────────────────────────────────────────────────

Write-Host "Acquiring bearer token for Azure AI Search..." -ForegroundColor Yellow
$token = Get-SearchToken
Write-Host "  Token acquired" -ForegroundColor Green
Write-Host ""

# ── Step 1: Data Source ──────────────────────────────────────────────────────

Write-Host "Step 1/4: Creating data source (pdf-datasource)..." -ForegroundColor Yellow

$dataSourceBody = @{
    name = "pdf-datasource"
    type = "azureblob"
    credentials = @{
        connectionString = "ResourceId=$storageResourceId;"
    }
    container = @{
        name = $BlobContainer
    }
} | ConvertTo-Json -Depth 5

Invoke-SearchApi -Endpoint $searchEndpoint -Path "/datasources/pdf-datasource" -Token $token -Body $dataSourceBody
Write-Host "  Data source created (MI-based, no storage keys)" -ForegroundColor Green

# ── Step 2: Index ────────────────────────────────────────────────────────────

Write-Host "Step 2/5: Creating index ($IndexName)..." -ForegroundColor Yellow

$indexBody = @{
    name = $IndexName
    fields = @(
        @{ name = "content_id";       type = "Edm.String"; key = $true; analyzer = "keyword" }
        @{ name = "text_document_id"; type = "Edm.String"; filterable = $true; retrievable = $true }
        @{ name = "image_document_id"; type = "Edm.String"; filterable = $true; retrievable = $true }
        @{ name = "document_title";   type = "Edm.String"; searchable = $true; retrievable = $true }
        @{ name = "content_text";     type = "Edm.String"; searchable = $true; retrievable = $true }
        @{ name = "content_path";     type = "Edm.String"; retrievable = $true }
        @{
            name = "location_metadata"
            type = "Edm.ComplexType"
            fields = @(
                @{ name = "pageNumberFrom";   type = "Edm.Int32";  retrievable = $true; filterable = $true }
                @{ name = "pageNumberTo";     type = "Edm.Int32";  retrievable = $true; filterable = $true }
                @{ name = "ordinalPosition";  type = "Edm.Int32";  retrievable = $true }
                @{ name = "source";           type = "Edm.String"; retrievable = $true }
            )
        }
        @{
            name = "content_embedding"
            type = "Collection(Edm.Single)"
            searchable = $true
            retrievable = $false
            dimensions = 3072
            vectorSearchProfile = "hnsw-profile"
        }
    )
    vectorSearch = @{
        profiles = @(
            @{ name = "hnsw-profile"; algorithm = "hnsw-config"; vectorizer = "ai-foundry-vectorizer" }
        )
        algorithms = @(
            @{ name = "hnsw-config"; kind = "hnsw"; hnswParameters = @{ metric = "cosine" } }
        )
        vectorizers = @(
            @{
                name = "ai-foundry-vectorizer"
                kind = "azureOpenAI"
                azureOpenAIParameters = @{
                    resourceUri  = $aiFoundryEndpoint
                    deploymentId = "embeddings"
                    modelName    = "text-embedding-3-large"
                    authIdentity = $null
                }
            }
        )
    }
    semantic = @{
        configurations = @(
            @{
                name = "semantic-config"
                prioritizedFields = @{
                    prioritizedContentFields  = @( @{ fieldName = "content_text" } )
                    titleField     = @{ fieldName = "document_title" }
                    prioritizedKeywordsFields = @( @{ fieldName = "document_title" } )
                }
            }
        )
    }
} | ConvertTo-Json -Depth 10

Invoke-SearchApi -Endpoint $searchEndpoint -Path "/indexes/$IndexName" -Token $token -Body $indexBody
Write-Host "  Index created (3072-d HNSW, AI Foundry vectorizer with keyless auth)" -ForegroundColor Green

# ── Step 3: Skillset ────────────────────────────────────────────────────────

Write-Host "Step 3/5: Creating skillset (pdf-skillset)..." -ForegroundColor Yellow

$skillsetBody = @{
    name = "pdf-skillset"
    description = "Content Understanding (extraction + chunking) + embeddings + image captions (chat completion). Keyless billing via AIServicesByIdentity."
    cognitiveServices = @{
        "@odata.type" = "#Microsoft.Azure.Search.AIServicesByIdentity"
        description   = "Keyless billing via search service system-assigned managed identity (preview)"
        subdomainUrl  = $aiServicesEndpoint
        identity      = $null
    }
    knowledgeStore = @{
        storageConnectionString = "ResourceId=$storageResourceId;"
        projections = @(
            @{
                files = @(
                    @{
                        storageContainer = $ImageContainer
                        source           = "/document/normalized_images/*"
                    }
                )
            }
        )
    }
    skills = @(
        @{
            "@odata.type"       = "#Microsoft.Skills.Util.ContentUnderstandingSkill"
            name                = "content-understanding-skill"
            description         = "Uses Azure Content Understanding for structure-aware extraction AND built-in chunking with image extraction and location metadata. Outputs Markdown for tables/figures, supports cross-page tables, and chunks spanning page boundaries."
            context             = "/document"
            extractionOptions   = @("images", "locationMetadata")
            chunkingProperties  = @{
                unit          = "characters"
                maximumLength = 2000
                overlapLength = 200
            }
            inputs  = @( @{ name = "file_data"; source = "/document/file_data" } )
            outputs = @(
                @{ name = "text_sections";     targetName = "text_sections" }
                @{ name = "normalized_images"; targetName = "normalized_images" }
            )
        }
        @{
            "@odata.type"  = "#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill"
            name           = "text-embedding-skill"
            context        = "/document/text_sections/*"
            resourceUri    = $aiFoundryEndpoint
            deploymentId   = "embeddings"
            modelName      = "text-embedding-3-large"
            dimensions     = 3072
            authIdentity   = $null
            inputs  = @( @{ name = "text"; source = "/document/text_sections/*/content" } )
            outputs = @( @{ name = "embedding"; targetName = "content_embedding" } )
        }
        @{
            "@odata.type" = "#Microsoft.Skills.Custom.ChatCompletionSkill"
            name          = "image-verbalization-skill"
            context       = "/document/normalized_images/*"
            uri           = "$($aiFoundryEndpoint.TrimEnd('/'))/openai/deployments/chat/chat/completions?api-version=2024-10-21"
            authIdentity  = $null
            inputs = @(
                @{ name = "image";         source = "/document/normalized_images/*/data" }
                @{ name = "imageDetail";   source = "='high'" }
                @{ name = "systemMessage"; source = "='You are a document analyst. Describe all text, charts, tables, diagrams, and meaningful visual elements in detail. Be concise but complete.'" }
                @{ name = "userMessage";   source = "='Describe the content of this image.'" }
            )
            outputs = @(
                @{ name = "response"; targetName = "verbalized_image" }
            )
            responseFormat          = @{ type = "text" }
            commonModelParameters   = @{ temperature = 0 }
        }
        @{
            "@odata.type"  = "#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill"
            name           = "image-embedding-skill"
            context        = "/document/normalized_images/*"
            resourceUri    = $aiFoundryEndpoint
            deploymentId   = "embeddings"
            modelName      = "text-embedding-3-large"
            dimensions     = 3072
            authIdentity   = $null
            inputs  = @( @{ name = "text"; source = "/document/normalized_images/*/verbalized_image" } )
            outputs = @( @{ name = "embedding"; targetName = "content_embedding" } )
        }
    )
    indexProjections = @{
        selectors = @(
            @{
                targetIndexName     = $IndexName
                parentKeyFieldName  = "text_document_id"
                sourceContext        = "/document/text_sections/*"
                mappings = @(
                    @{ name = "content_text";      source = "/document/text_sections/*/content" }
                    @{ name = "content_embedding"; source = "/document/text_sections/*/content_embedding" }
                    @{ name = "content_path";      source = "/document/metadata_storage_path" }
                    @{ name = "document_title";    source = "/document/metadata_storage_name" }
                    @{ name = "location_metadata"; source = "/document/text_sections/*/locationMetadata" }
                )
            }
            @{
                targetIndexName     = $IndexName
                parentKeyFieldName  = "image_document_id"
                sourceContext        = "/document/normalized_images/*"
                mappings = @(
                    @{ name = "content_text";      source = "/document/normalized_images/*/verbalized_image" }
                    @{ name = "content_embedding"; source = "/document/normalized_images/*/content_embedding" }
                    @{ name = "content_path";      source = "/document/metadata_storage_path" }
                    @{ name = "document_title";    source = "/document/metadata_storage_name" }
                    @{ name = "location_metadata"; source = "/document/normalized_images/*/locationMetadata" }
                )
            }
        )
        parameters = @{
            projectionMode = "skipIndexingParentDocuments"
        }
    }
} | ConvertTo-Json -Depth 15

Invoke-SearchApi -Endpoint $searchEndpoint -Path "/skillsets/pdf-skillset" -Token $token -Body $skillsetBody
Write-Host "  Skillset created (AIServicesByIdentity, Content Understanding + Embeddings + ChatCompletion)" -ForegroundColor Green

# ── Step 4: Indexer ──────────────────────────────────────────────────────────

Write-Host "Step 4/5: Creating indexer (pdf-indexer)..." -ForegroundColor Yellow

# NOTE: Images are extracted by Content Understanding (extractionOptions: ["images"]),
# which provides location metadata (page, bounding polygon) for each image.
# To switch back to simpler/cheaper indexer-based extraction, add
#   imageAction = "generateNormalizedImages"
# to the indexer configuration below, and remove "images" from the CU skill's extractionOptions.
$indexerBody = @{
    name            = "pdf-indexer"
    dataSourceName  = "pdf-datasource"
    skillsetName    = "pdf-skillset"
    targetIndexName = $IndexName
    schedule        = $null
    parameters = @{
        batchSize     = 1
        configuration = @{
            dataToExtract              = "contentAndMetadata"
            allowSkillsetToReadFileData = $true
        }
    }
    fieldMappings = @(
        @{ sourceFieldName = "metadata_storage_name"; targetFieldName = "document_title" }
        @{ sourceFieldName = "metadata_storage_path"; targetFieldName = "content_path" }
    )
    outputFieldMappings = @()
} | ConvertTo-Json -Depth 5

Invoke-SearchApi -Endpoint $searchEndpoint -Path "/indexers/pdf-indexer" -Token $token -Body $indexerBody
Write-Host "  Indexer created (manual trigger, MI auth to blob)" -ForegroundColor Green

# ── Step 5: Trigger indexer run ──────────────────────────────────────────────

Write-Host "Step 5/5: Triggering indexer run..." -ForegroundColor Yellow

try {
    Invoke-SearchApi -Endpoint $searchEndpoint -Path "/indexers/pdf-indexer/run" -Token $token -Body "{}" -Method "POST"
    Write-Host "  Indexer run triggered" -ForegroundColor Green
} catch {
    Write-Host "  Indexer trigger failed (no documents in container yet?)" -ForegroundColor DarkYellow
}

# ── Summary ──────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "Search pipeline deployed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Pipeline:" -ForegroundColor Cyan
Write-Host "  Blob Storage ($BlobContainer) -> Content Understanding (extraction + chunking, ~2000 chars) -> Embeddings (3072d)" -ForegroundColor White
Write-Host "                                -> Normalized Images -> Chat Completion (caption) -> Image Embeddings" -ForegroundColor White
Write-Host ""
Write-Host "Operational notes:" -ForegroundColor Cyan
Write-Host "  - If you see 'truncated extracted text', it's a SKU extraction limit; consider S1+." -ForegroundColor White
Write-Host "  - Ensure the search service identity has 'Cognitive Services OpenAI User' on your Azure AI Foundry resource." -ForegroundColor White
Write-Host "  - ChatCompletion skill is Preview; if you need GA, replace with ImageAnalysisSkill('description')." -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Upload PDF files to the '$BlobContainer' container in storage account '$storageAccount'" -ForegroundColor White
Write-Host "  2. Re-run the indexer:" -ForegroundColor White
Write-Host "     az rest --method POST --url '${searchEndpoint}indexers/pdf-indexer/run?api-version=$apiVersion' --resource https://search.azure.com/" -ForegroundColor Gray
Write-Host "  3. Monitor indexer status:" -ForegroundColor White
Write-Host "     az rest --method GET --url '${searchEndpoint}indexers/pdf-indexer/status?api-version=$apiVersion' --resource https://search.azure.com/" -ForegroundColor Gray
