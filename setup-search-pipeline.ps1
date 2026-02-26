# setup-search-pipeline.ps1
# Deploys the Azure AI Search integrated vectorization pipeline (data source, index, skillset, indexer)
# using Foundry-aligned patterns: keyless billing (AIServicesByIdentity), managed identity auth,
# Document Layout skill, ChatCompletion (GenAI Prompt) skill, and Azure OpenAI Embedding skill.
#
# Prerequisites:
#   1. Run 'azd up' first to deploy infrastructure.
#   2. Run 'azd env get-values' to confirm environment values are available.
#   3. RBAC roles must be propagated (may take a few minutes after deployment).
#
# API version: 2025-11-01-preview (required for Document Layout skill, ChatCompletion skill,
# and AIServicesByIdentity keyless skillset billing — currently in public preview).

param(
    [string]$IndexName = "pdf-index",
    [string]$BlobContainer = "pdfs",
    [string]$ImageContainer = "pdf-images",
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$apiVersion = "2025-11-01-preview"

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
$openAiEndpoint    = Get-AzdValue "AZURE_OPENAI_ENDPOINT"
$aiServicesEndpoint = Get-AzdValue "AI_FOUNDRY_SERVICES_SUBDOMAIN_URL"

# Fallback: if subdomain URL not available, construct from services endpoint
if (-not $aiServicesEndpoint -or $aiServicesEndpoint -eq "") {
    $aiServicesEndpoint = Get-AzdValue "AI_FOUNDRY_SERVICES_ENDPOINT"
}

$storageResourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Storage/storageAccounts/$storageAccount"

Write-Host "  Search Endpoint:    $searchEndpoint" -ForegroundColor Cyan
Write-Host "  Storage Account:    $storageAccount" -ForegroundColor Cyan
Write-Host "  OpenAI Endpoint:    $openAiEndpoint" -ForegroundColor Cyan
Write-Host "  AI Services URL:    $aiServicesEndpoint" -ForegroundColor Cyan
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

Write-Host "Step 2/4: Creating index ($IndexName)..." -ForegroundColor Yellow

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
                @{ name = "page_number";       type = "Edm.Int32";  retrievable = $true; filterable = $true }
                @{ name = "bounding_polygons"; type = "Edm.String"; retrievable = $true }
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
            @{ name = "hnsw-profile"; algorithm = "hnsw-config"; vectorizer = "openai-vectorizer" }
        )
        algorithms = @(
            @{ name = "hnsw-config"; kind = "hnsw"; hnswParameters = @{ metric = "cosine" } }
        )
        vectorizers = @(
            @{
                name = "openai-vectorizer"
                kind = "azureOpenAI"
                azureOpenAIParameters = @{
                    resourceUri  = $openAiEndpoint
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
Write-Host "  Index created (3072-d HNSW, OpenAI vectorizer with keyless auth)" -ForegroundColor Green

# ── Step 3: Skillset ────────────────────────────────────────────────────────

Write-Host "Step 3/4: Creating skillset (pdf-skillset)..." -ForegroundColor Yellow

$skillsetBody = @{
    name = "pdf-skillset"
    description = "Foundry-aligned pipeline: Document Layout for text/image extraction, GPT-4o for image verbalization, text-embedding-3-large for vector embeddings. Uses AIServicesByIdentity for keyless billing."
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
            "@odata.type"       = "#Microsoft.Skills.Util.DocumentIntelligenceLayoutSkill"
            name                = "doc-layout-skill"
            context             = "/document"
            outputFormat        = "text"
            extractionOptions   = @("images", "locationMetadata")
            inputs  = @( @{ name = "file_data"; source = "/document/file_data" } )
            outputs = @(
                @{ name = "text_sections";     targetName = "text_sections" }
                @{ name = "normalized_images"; targetName = "normalized_images" }
            )
        }
        @{
            "@odata.type" = "#Microsoft.Skills.Custom.ChatCompletionSkill"
            name          = "image-verbalization-skill"
            context       = "/document/normalized_images/*"
            uri           = "$openAiEndpoint/openai/deployments/chat/chat/completions"
            authIdentity  = $null
            inputs = @(
                @{ name = "image";         source = "/document/normalized_images/*/data" }
                @{ name = "imageDetail";   source = "='high'" }
                @{ name = "systemMessage"; source = "='You are a document analyst. Describe all text, charts, tables, diagrams, and meaningful visual elements in detail. Be concise but complete.'" }
                @{ name = "userMessage";   source = "='Describe the content of this image.'" }
            )
            outputs = @(
                @{ name = "response"; targetName = "verbalized_text" }
            )
            responseFormat          = @{ type = "text" }
            commonModelParameters   = @{ temperature = 0.3; maxTokens = 1024 }
        }
        @{
            "@odata.type"  = "#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill"
            name           = "text-embedding-skill"
            context        = "/document/text_sections/*"
            resourceUri    = $openAiEndpoint
            deploymentId   = "embeddings"
            modelName      = "text-embedding-3-large"
            dimensions     = 3072
            authIdentity   = $null
            inputs  = @( @{ name = "text"; source = "/document/text_sections/*/content" } )
            outputs = @( @{ name = "embedding"; targetName = "content_embedding" } )
        }
        @{
            "@odata.type"  = "#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill"
            name           = "image-embedding-skill"
            context        = "/document/normalized_images/*"
            resourceUri    = $openAiEndpoint
            deploymentId   = "embeddings"
            modelName      = "text-embedding-3-large"
            dimensions     = 3072
            authIdentity   = $null
            inputs  = @( @{ name = "text"; source = "/document/normalized_images/*/verbalized_text" } )
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
                    @{
                        name          = "location_metadata"
                        source        = $null
                        sourceContext = "/document/text_sections/*"
                        inputs = @(
                            @{ name = "page_number";       source = "/document/text_sections/*/pageNumber" }
                            @{ name = "bounding_polygons"; source = "/document/text_sections/*/boundingPolygons" }
                        )
                    }
                )
            }
            @{
                targetIndexName     = $IndexName
                parentKeyFieldName  = "image_document_id"
                sourceContext        = "/document/normalized_images/*"
                mappings = @(
                    @{ name = "content_text";      source = "/document/normalized_images/*/verbalized_text" }
                    @{ name = "content_embedding"; source = "/document/normalized_images/*/content_embedding" }
                    @{ name = "content_path";      source = "/document/normalized_images/*/storagePath" }
                    @{ name = "document_title";    source = "/document/metadata_storage_name" }
                    @{
                        name          = "location_metadata"
                        source        = $null
                        sourceContext = "/document/normalized_images/*"
                        inputs = @(
                            @{ name = "page_number";       source = "/document/normalized_images/*/pageNumber" }
                            @{ name = "bounding_polygons"; source = "/document/normalized_images/*/boundingPolygons" }
                        )
                    }
                )
            }
        )
        parameters = @{
            projectionMode = "skipIndexingParentDocuments"
        }
    }
} | ConvertTo-Json -Depth 15

Invoke-SearchApi -Endpoint $searchEndpoint -Path "/skillsets/pdf-skillset" -Token $token -Body $skillsetBody
Write-Host "  Skillset created (AIServicesByIdentity keyless billing, Document Layout + ChatCompletion + Embedding)" -ForegroundColor Green

# ── Step 4: Indexer ──────────────────────────────────────────────────────────

Write-Host "Step 4/4: Creating indexer (pdf-indexer)..." -ForegroundColor Yellow

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
            imageAction                = "generateNormalizedImages"
            allowSkillsetToReadFileData = $true
        }
    }
    fieldMappings = @(
        @{ sourceFieldName = "metadata_storage_path"; targetFieldName = "content_id" }
        @{ sourceFieldName = "metadata_storage_name"; targetFieldName = "document_title" }
    )
    outputFieldMappings = @()
} | ConvertTo-Json -Depth 5

Invoke-SearchApi -Endpoint $searchEndpoint -Path "/indexers/pdf-indexer" -Token $token -Body $indexerBody
Write-Host "  Indexer created (manual trigger, MI auth to blob)" -ForegroundColor Green

# ── Summary ──────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "Search pipeline deployed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Pipeline architecture:" -ForegroundColor Cyan
Write-Host "  Blob Storage (pdfs) --> Document Layout Skill --> Text Split" -ForegroundColor White
Write-Host "                      --> Image Extraction --> GPT-4o Verbalization" -ForegroundColor White
Write-Host "                      --> text-embedding-3-large (3072d) --> Index" -ForegroundColor White
Write-Host ""
Write-Host "Foundry patterns used:" -ForegroundColor Cyan
Write-Host "  - AIServicesByIdentity: keyless skillset billing via system MI" -ForegroundColor White
Write-Host "  - authIdentity: null on all skills/vectorizer (no API keys)" -ForegroundColor White
Write-Host "  - ResourceId connection string (MI-based blob access)" -ForegroundColor White
Write-Host "  - Index Projections with skipIndexingParentDocuments" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Upload PDF files to the '$BlobContainer' container in storage account '$storageAccount'" -ForegroundColor White
Write-Host "  2. Run the indexer:" -ForegroundColor White
Write-Host "     az rest --method POST --url '${searchEndpoint}indexers/pdf-indexer/run?api-version=$apiVersion' --resource https://search.azure.com/" -ForegroundColor Gray
Write-Host "  3. Monitor indexer status:" -ForegroundColor White
Write-Host "     az rest --method GET --url '${searchEndpoint}indexers/pdf-indexer/status?api-version=$apiVersion' --resource https://search.azure.com/" -ForegroundColor Gray
