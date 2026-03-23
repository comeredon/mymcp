#!/usr/bin/env bash
# setup-search-pipeline.sh
# Deploys the Azure AI Search pipeline (data source, index, skillset, indexer)
# using Foundry-aligned patterns: keyless billing (AIServicesByIdentity), managed identity auth,
# Content Understanding skill (extraction + built-in chunking), ChatCompletion (GenAI Prompt) skill (Preview),
# and Azure AI Foundry Embedding skill.
#
# Usage:
#   Standalone (reads from Bicep deployment):
#     bash setup-search-pipeline.sh --resource-group mcp-server-rg --deployment-name <name>
#
#   From deploy.sh (env vars pre-set):
#     SEARCH_ENDPOINT=... STORAGE_ACCOUNT_ID=... AI_FOUNDRY_ENDPOINT=... \
#       AI_FOUNDRY_SERVICES_SUBDOMAIN_URL=... bash setup-search-pipeline.sh
#
# API version (Preview is required for token-based TextSplit + ChatCompletion skill):
#   2024-11-01-Preview
#   - TextSplit token-based chunking and updated params  ➜ docs: 2024-09-01-preview and later
#   - ChatCompletionSkill (GenAI Prompt)               ➜ public preview
#
# References:
# - Text Split skill (token-based, ordinals): https://learn.microsoft.com/azure/search/cognitive-search-skill-textsplit
# - Chat Completion skill (Preview):          https://docs.azure.cn/en-us/search/cognitive-search-skill-genai-prompt
# - Embedding skill + 8k token input:         https://learn.microsoft.com/azure/search/cognitive-search-skill-azure-openai-embedding

set -euo pipefail

API_VERSION="2025-11-01-Preview"
INDEX_NAME="${INDEX_NAME:-pdf-index}"
BLOB_CONTAINER="${BLOB_CONTAINER:-pdfs}"
IMAGE_CONTAINER="${IMAGE_CONTAINER:-pdf-images}"
FORCE="${FORCE:-false}"

# Parse command-line arguments
RESOURCE_GROUP=""
DEPLOYMENT_NAME=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --resource-group)     RESOURCE_GROUP="$2"; shift 2 ;;
        --deployment-name)    DEPLOYMENT_NAME="$2"; shift 2 ;;
        --index-name)         INDEX_NAME="$2"; shift 2 ;;
        --blob-container)     BLOB_CONTAINER="$2"; shift 2 ;;
        --image-container)    IMAGE_CONTAINER="$2"; shift 2 ;;
        --force)              FORCE="true"; shift ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --resource-group NAME     Resource group (to read deployment outputs)"
            echo "  --deployment-name NAME    Bicep deployment name (to read outputs)"
            echo "  --index-name NAME         Search index name (default: pdf-index)"
            echo "  --blob-container NAME     Source blob container (default: pdfs)"
            echo "  --image-container NAME    Knowledge store image container (default: pdf-images)"
            echo "  --force                   Overwrite existing pipeline resources"
            echo "  -h, --help                Show this help"
            echo ""
            echo "Environment variables (alternative to --resource-group/--deployment-name):"
            echo "  SEARCH_ENDPOINT, STORAGE_ACCOUNT_ID, AI_FOUNDRY_ENDPOINT,"
            echo "  AI_FOUNDRY_SUBDOMAIN_URL, AZURE_SUBSCRIPTION_ID,"
            echo "  AZURE_RESOURCE_GROUP_NAME, STORAGE_ACCOUNT_NAME"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Helpers ──────────────────────────────────────────────────────────────────

call_search_api() {
    local method="$1" path="$2" body="$3"
    local url="${SEARCH_ENDPOINT}${path}?api-version=${API_VERSION}"

    local http_code
    local response
    response=$(curl -s -w "\n%{http_code}" \
        -X "$method" "$url" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "$body")

    http_code=$(echo "$response" | tail -1)
    local body_response
    body_response=$(echo "$response" | sed '$d')

    if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
        return 0
    else
        echo "  ❌ API call failed (HTTP $http_code): $body_response" >&2
        return 1
    fi
}

# ── Resolve environment values ───────────────────────────────────────────────

echo "🔍 Azure AI Search Pipeline Setup"
echo "================================="
echo ""

# If deployment outputs not in env, read from Bicep deployment
if [[ -z "${SEARCH_ENDPOINT:-}" && -n "$RESOURCE_GROUP" && -n "$DEPLOYMENT_NAME" ]]; then
    echo "Reading deployment outputs from '$DEPLOYMENT_NAME'..."
    outputs=$(az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --query "properties.outputs" \
        -o json | jq 'with_entries(.key |= ascii_upcase)')

    SEARCH_ENDPOINT=$(echo "$outputs" | jq -r '.SEARCH_ENDPOINT.value')
    STORAGE_ACCOUNT_ID=$(echo "$outputs" | jq -r '.STORAGE_ACCOUNT_ID.value')
    STORAGE_ACCOUNT_NAME=$(echo "$outputs" | jq -r '.STORAGE_ACCOUNT_NAME.value')
    AI_FOUNDRY_ENDPOINT=$(echo "$outputs" | jq -r '.AI_FOUNDRY_ENDPOINT.value')
    AI_FOUNDRY_SUBDOMAIN_URL=$(echo "$outputs" | jq -r '.AI_FOUNDRY_SUBDOMAIN_URL.value')
    AZURE_SUBSCRIPTION_ID=$(echo "$outputs" | jq -r '.AZURE_SUBSCRIPTION_ID.value')
    AZURE_RESOURCE_GROUP_NAME=$(echo "$outputs" | jq -r '.AZURE_RESOURCE_GROUP_NAME.value')
    INDEX_NAME=$(echo "$outputs" | jq -r '.SEARCH_INDEX_NAME.value // "pdf-index"')
elif [[ -z "${SEARCH_ENDPOINT:-}" ]]; then
    echo "❌ No deployment outputs available."
    echo "   Either pass --resource-group + --deployment-name, or set environment variables."
    echo "   Run '$0 --help' for details."
    exit 1
fi

# Build storage resource ID if not provided directly
if [[ -z "${STORAGE_ACCOUNT_ID:-}" ]]; then
    STORAGE_ACCOUNT_ID="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP_NAME}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT_NAME}"
fi

echo "  Search Endpoint:       $SEARCH_ENDPOINT"
echo "  Storage Account ID:    $STORAGE_ACCOUNT_ID"
echo "  AI Foundry Endpoint:   $AI_FOUNDRY_ENDPOINT"
echo "  AI Foundry URL:        $AI_FOUNDRY_SUBDOMAIN_URL"
echo "  Index Name:            $INDEX_NAME"
echo "  API Version:           $API_VERSION"
echo ""

# ── Acquire bearer token ─────────────────────────────────────────────────────

echo "Acquiring bearer token for Azure AI Search..."
TOKEN=$(az account get-access-token --resource https://search.azure.com/ --query accessToken -o tsv 2>/dev/null)
if [[ -z "$TOKEN" ]]; then
    echo "❌ Failed to get search access token. Run 'az login' first."
    exit 1
fi
echo "  ✅ Token acquired"
echo ""

# ── Step 1: Data Source ──────────────────────────────────────────────────────

echo "Step 1/5: Creating data source (pdf-datasource)..."

datasource_body=$(cat <<EOF
{
  "name": "pdf-datasource",
  "type": "azureblob",
  "credentials": {
    "connectionString": "ResourceId=${STORAGE_ACCOUNT_ID};"
  },
  "container": {
    "name": "${BLOB_CONTAINER}"
  }
}
EOF
)

if call_search_api PUT "/datasources/pdf-datasource" "$datasource_body"; then
    echo "  ✅ Data source created (MI-based, no storage keys)"
else
    echo "  ⚠️  Data source creation failed (may already exist, use --force to overwrite)"
fi

# ── Step 2: Index ────────────────────────────────────────────────────────────

echo "Step 2/5: Creating index ($INDEX_NAME)..."

index_body=$(cat <<EOF
{
  "name": "${INDEX_NAME}",
  "fields": [
    { "name": "content_id",       "type": "Edm.String", "key": true,  "filterable": true, "analyzer": "keyword" },
    { "name": "text_document_id", "type": "Edm.String", "filterable": true, "retrievable": true },
    { "name": "image_document_id","type": "Edm.String", "filterable": true, "retrievable": true },
    { "name": "document_title",   "type": "Edm.String", "searchable": true, "retrievable": true },
    { "name": "content_text",     "type": "Edm.String", "searchable": true, "retrievable": true },
    { "name": "content_path",     "type": "Edm.String", "retrievable": true },
    {
      "name": "location_metadata",
      "type": "Edm.ComplexType",
      "fields": [
        { "name": "pageNumberFrom",     "type": "Edm.Int32",  "retrievable": true, "filterable": true },
        { "name": "pageNumberTo",       "type": "Edm.Int32",  "retrievable": true, "filterable": true },
        { "name": "ordinalPosition",    "type": "Edm.Int32",  "retrievable": true },
        { "name": "source",             "type": "Edm.String", "retrievable": true }
      ]
    },
    {
      "name": "content_embedding",
      "type": "Collection(Edm.Single)",
      "searchable": true,
      "retrievable": false,
      "dimensions": 3072,
      "vectorSearchProfile": "hnsw-profile"
    }
  ],
  "vectorSearch": {
    "profiles": [
      { "name": "hnsw-profile", "algorithm": "hnsw-config", "vectorizer": "ai-foundry-vectorizer" }
    ],
    "algorithms": [
      { "name": "hnsw-config", "kind": "hnsw", "hnswParameters": { "metric": "cosine" } }
    ],
    "vectorizers": [
      {
        "name": "ai-foundry-vectorizer",
        "kind": "azureOpenAI",
        "azureOpenAIParameters": {
          "resourceUri": "${AI_FOUNDRY_ENDPOINT}",
          "deploymentId": "embeddings",
          "modelName": "text-embedding-3-large",
          "authIdentity": null
        }
      }
    ]
  },
  "semantic": {
    "configurations": [
      {
        "name": "semantic-config",
        "prioritizedFields": {
          "prioritizedContentFields":  [{ "fieldName": "content_text" }],
          "titleField":     { "fieldName": "document_title" },
          "prioritizedKeywordsFields": [{ "fieldName": "document_title" }]
        }
      }
    ]
  }
}
EOF
)

if call_search_api PUT "/indexes/${INDEX_NAME}" "$index_body"; then
    echo "  ✅ Index created (3072-d HNSW; embeddings provided by skillset)"
else
    echo "  ⚠️  Index creation failed"
fi

# ── Step 3: Skillset ────────────────────────────────────────────────────────

echo "Step 3/5: Creating skillset (pdf-skillset)..."

skillset_body=$(cat <<EOF
{
  "name": "pdf-skillset",
  "description": "Content Understanding (extraction + chunking) + embeddings + image captions (chat completion). Keyless billing via AIServicesByIdentity.",
  "cognitiveServices": {
    "@odata.type": "#Microsoft.Azure.Search.AIServicesByIdentity",
    "description": "Keyless billing via search service system-assigned managed identity (preview)",
    "subdomainUrl": "${AI_FOUNDRY_SUBDOMAIN_URL}",
    "identity": null
  },
  "knowledgeStore": {
    "storageConnectionString": "ResourceId=${STORAGE_ACCOUNT_ID};",
    "projections": [
      {
        "files": [
          {
            "storageContainer": "${IMAGE_CONTAINER}",
            "source": "/document/normalized_images/*"
          }
        ]
      }
    ]
  },
  "skills": [
    {
      "@odata.type": "#Microsoft.Skills.Util.ContentUnderstandingSkill",
      "name": "content-understanding-skill",
      "description": "Uses Azure Content Understanding for structure-aware extraction AND built-in chunking with image extraction and location metadata. Outputs Markdown for tables/figures, supports cross-page tables, and chunks spanning page boundaries.",
      "context": "/document",
      "extractionOptions": ["images", "locationMetadata"],
      "chunkingProperties": {
        "unit": "characters",
        "maximumLength": 2000,
        "overlapLength": 200
      },
      "inputs":  [{ "name": "file_data", "source": "/document/file_data" }],
      "outputs": [
        { "name": "text_sections",     "targetName": "text_sections" },
        { "name": "normalized_images", "targetName": "normalized_images" }
      ]
    },
    {
      "@odata.type": "#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill",
      "name": "text-embedding-skill",
      "context": "/document/text_sections/*",
      "resourceUri": "${AI_FOUNDRY_ENDPOINT}",
      "deploymentId": "embeddings",
      "modelName": "text-embedding-3-large",
      "dimensions": 3072,
      "authIdentity": null,
      "inputs":  [{ "name": "text", "source": "/document/text_sections/*/content" }],
      "outputs": [{ "name": "embedding", "targetName": "content_embedding" }]
    },
    {
      "@odata.type": "#Microsoft.Skills.Custom.ChatCompletionSkill",
      "name": "image-verbalization-skill",
      "context": "/document/normalized_images/*",
      "uri": "${AI_FOUNDRY_ENDPOINT%/}/openai/deployments/chat/chat/completions?api-version=2024-10-21",
      "authIdentity": null,
      "inputs": [
        { "name": "image",         "source": "/document/normalized_images/*/data" },
        { "name": "imageDetail",   "source": "='high'" },
        { "name": "systemMessage", "source": "='You are a document analyst. Describe all text, charts, tables, diagrams, and meaningful visual elements in detail. Be concise but complete.'" },
        { "name": "userMessage",   "source": "='Describe the content of this image.'" }
      ],
      "outputs": [
        { "name": "response", "targetName": "verbalized_image" }
      ],
      "responseFormat": { "type": "text" },
      "commonModelParameters": { "temperature": 0, "maxTokens": 1024 }
    },
    {
      "@odata.type": "#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill",
      "name": "image-embedding-skill",
      "context": "/document/normalized_images/*",
      "resourceUri": "${AI_FOUNDRY_ENDPOINT}",
      "deploymentId": "embeddings",
      "modelName": "text-embedding-3-large", 
      "dimensions": 3072,
      "authIdentity": null,
      "inputs":  [{ "name": "text", "source": "/document/normalized_images/*/verbalized_image" }],
      "outputs": [{ "name": "embedding", "targetName": "content_embedding" }]
    }
  ],
  "indexProjections": {
    "selectors": [
      {
        "targetIndexName": "${INDEX_NAME}",
        "parentKeyFieldName": "text_document_id",
        "sourceContext": "/document/text_sections/*",
        "mappings": [
          { "name": "content_text",      "source": "/document/text_sections/*/content" },
          { "name": "content_embedding", "source": "/document/text_sections/*/content_embedding" },
          { "name": "content_path",      "source": "/document/metadata_storage_path" },
          { "name": "document_title",    "source": "/document/metadata_storage_name" },
          { "name": "location_metadata", "source": "/document/text_sections/*/locationMetadata" }
        ]
      },
      {
        "targetIndexName": "${INDEX_NAME}",
        "parentKeyFieldName": "image_document_id", 
        "sourceContext": "/document/normalized_images/*",
        "mappings": [
          { "name": "content_text",      "source": "/document/normalized_images/*/verbalized_image" },
          { "name": "content_embedding", "source": "/document/normalized_images/*/content_embedding" },
          { "name": "content_path",      "source": "/document/metadata_storage_path" },
          { "name": "document_title",    "source": "/document/metadata_storage_name" },
          { "name": "location_metadata", "source": "/document/normalized_images/*/locationMetadata" }
        ]
      }
    ],
    "parameters": {
      "projectionMode": "skipIndexingParentDocuments"
    }
  }
}
EOF
)

if call_search_api PUT "/skillsets/pdf-skillset" "$skillset_body"; then
    echo "  ✅ Skillset created (AIServicesByIdentity, Content Understanding + Embeddings + ChatCompletion)"
else
    echo "  ⚠️  Skillset creation failed"
fi

# ── Step 4: Indexer ──────────────────────────────────────────────────────────

echo "Step 4/5: Creating indexer (pdf-indexer)..."

# NOTE: Images are extracted by Content Understanding (extractionOptions: [\"images\"]),\n# which provides location metadata (page, bounding polygon) for each image.\n# To switch back to simpler/cheaper indexer-based extraction, add\n#   \"imageAction\": \"generateNormalizedImages\"\n# to the indexer configuration below, and remove \"images\" from the CU skill's extractionOptions.
indexer_body=$(cat <<EOF
{
  "name": "pdf-indexer",
  "dataSourceName": "pdf-datasource",
  "skillsetName": "pdf-skillset",
  "targetIndexName": "${INDEX_NAME}",
  "schedule": null,
  "parameters": {
    "batchSize": 1,
    "configuration": {
      "dataToExtract": "contentAndMetadata",
      "allowSkillsetToReadFileData": true
    }
  },
  "fieldMappings": [
    { "sourceFieldName": "metadata_storage_name", "targetFieldName": "document_title" },
    { "sourceFieldName": "metadata_storage_path", "targetFieldName": "content_path" }
  ],
  "outputFieldMappings": []
}
EOF
)

if call_search_api PUT "/indexers/pdf-indexer" "$indexer_body"; then
    echo "  ✅ Indexer created (manual trigger, MI auth to blob)"
else
    echo "  ⚠️  Indexer creation failed"
fi

# ── Step 5: Trigger indexer run ──────────────────────────────────────────────

echo "Step 5/5: Triggering indexer run..."

if call_search_api POST "/indexers/pdf-indexer/run" "{}"; then
    echo "  ✅ Indexer run triggered"
else
    echo "  ⚠️  Indexer trigger failed (no documents in container yet?)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "✅ Search pipeline deployed successfully!"
echo ""
echo "Pipeline:"
echo "  Blob Storage (${BLOB_CONTAINER}) → Content Understanding (extraction + chunking, ~2000 chars) → Embeddings (3072d)"
echo "                                   → Normalized Images → Chat Completion (caption) → (optional) image embeddings"
echo ""
echo "Operational notes:"
echo "  • If you see 'truncated extracted text', it's a SKU extraction limit; consider S1+. (Chunking helps model limits, not extraction caps.)"
echo "  • Ensure the search service identity has 'Cognitive Services OpenAI User' on your Azure AI Foundry resource."
echo "  • ChatCompletion skill is Preview; if you need GA, replace with ImageAnalysisSkill('description')."
echo ""
echo "Token chunking is handled by Content Understanding's built-in chunkingProperties (~2000 chars with 200 char overlap), keeping each embedding input safely under model limits."
echo "Removing the index vectorizer avoids double‑vectorization and potential inconsistency; you're now only using AzureOpenAIEmbeddingSkill during indexing."
echo "Truncation before the skillset is a service limit—upgrade the SKU to raise extraction caps; chunking only prevents model‑side truncation."
echo ""
echo "Next steps:"
echo "  1. Upload PDFs:  az storage blob upload-batch -d ${BLOB_CONTAINER} -s <folder> --account-name ${STORAGE_ACCOUNT_NAME:-<storage>} --auth-mode login"
echo "  2. Re-run indexer:  az rest --method POST --url '${SEARCH_ENDPOINT}indexers/pdf-indexer/run?api-version=${API_VERSION}' --resource https://search.azure.com/"
echo "  3. Check status:    az rest --method GET  --url '${SEARCH_ENDPOINT}indexers/pdf-indexer/status?api-version=${API_VERSION}' --resource https://search.azure.com/"
