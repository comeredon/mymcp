#!/usr/bin/env bash
# MCP Azure PDF Server - Unified Deployment Script
# Deploys all required Azure resources and the MCP server container

main() {
set -euo pipefail

# Default parameters
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-mcp}"
RESOURCE_GROUP_NAME="${RESOURCE_GROUP_NAME:-mcp-server-rg}"
LOCATION="${LOCATION:-swedencentral}"
SEARCH_INDEX_NAME="${SEARCH_INDEX_NAME:-pdf-index}"
API_KEY="${API_KEY:-}"
DEPLOY_APIM="${DEPLOY_APIM:-true}"
APIM_PUBLISHER_EMAIL="${APIM_PUBLISHER_EMAIL:-admin@contoso.com}"
APIM_PUBLISHER_NAME="${APIM_PUBLISHER_NAME:-Contoso}"
DEPLOY_VNET="${DEPLOY_VNET:-true}"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --environment-name)   ENVIRONMENT_NAME="$2"; shift 2 ;;
        --resource-group)     RESOURCE_GROUP_NAME="$2"; shift 2 ;;
        --location)           LOCATION="$2"; shift 2 ;;
        --search-index-name)  SEARCH_INDEX_NAME="$2"; shift 2 ;;
        --api-key)            API_KEY="$2"; shift 2 ;;
        --deploy-apim)        DEPLOY_APIM=true; shift ;;
        --no-apim)            DEPLOY_APIM=false; shift ;;
        --apim-publisher-email) APIM_PUBLISHER_EMAIL="$2"; shift 2 ;;
        --apim-publisher-name)  APIM_PUBLISHER_NAME="$2"; shift 2 ;;
        --deploy-vnet)        DEPLOY_VNET=true; shift ;;
        --no-vnet)            DEPLOY_VNET=false; shift ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --environment-name NAME     Environment name (default: mcp)"
            echo "  --resource-group NAME        Resource group name (default: mcp-server-rg)"
            echo "  --location LOCATION          Azure region (default: swedencentral)"
            echo "  --search-index-name NAME     Search index name (default: pdf-index)"
            echo "  --api-key KEY                API key for the MCP server"
            echo "  --deploy-apim                Deploy API Management (default: enabled)"
            echo "  --no-apim                    Skip API Management deployment"
            echo "  --apim-publisher-email EMAIL APIM publisher email (default: admin@contoso.com)"
            echo "  --apim-publisher-name NAME   APIM publisher name (default: Contoso)"
            echo "  --deploy-vnet                Deploy Virtual Network (default: enabled)"
            echo "  --no-vnet                    Skip Virtual Network deployment"
            echo "  -h, --help                   Show this help message"
            return 0
            ;;
        *) echo "Unknown option: $1"; return 1 ;;
    esac
done

echo "🚀 MCP Azure PDF Server - Unified Deployment"
echo "============================================"
echo ""

# Check if logged in to Azure
echo "Checking Azure authentication..."
login_status=$(az account show --query "user.name" -o tsv 2>/dev/null || true)
if [[ -z "$login_status" ]]; then
    echo "❌ Not logged in to Azure"
    echo "Please run: az login"
    return 1
fi
echo "✅ Logged in as: $login_status"

# Create resource group if it doesn't exist
echo ""
echo "Checking resource group '$RESOURCE_GROUP_NAME'..."
rg_exists=$(az group show --name "$RESOURCE_GROUP_NAME" --query "name" -o tsv 2>/dev/null || true)
if [[ -z "$rg_exists" ]]; then
    echo "Creating resource group '$RESOURCE_GROUP_NAME' in '$LOCATION'..."
    if ! az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION" --output none; then
        echo "❌ Failed to create resource group"
        return 1
    fi
    echo "✅ Resource group created"
else
    echo "✅ Resource group exists"
fi

# Build the project
echo ""
echo "Building the project..."
if ! npm run build; then
    echo "❌ Build failed!"
    return 1
fi
echo "✅ Build completed"

# Deploy infrastructure
echo ""
echo "Deploying Azure infrastructure..."
echo "This will create:"
echo "  - Azure AI Search service"
echo "  - Storage Account (for PDF documents)"
echo "  - Azure OpenAI (with embeddings & chat models)"
echo "  - Container Apps Environment"
echo "  - Container Registry"
echo "  - Log Analytics Workspace"
echo "  - Managed Identity (with RBAC roles)"
echo "  - MCP Server Container App"
if [[ "$DEPLOY_APIM" == "true" ]]; then
    echo "  - API Management"
fi
if [[ "$DEPLOY_VNET" == "true" ]]; then
    echo "  - Virtual Network"
fi
echo ""

deployment_name="mcp-deploy-$(date '+%Y%m%d-%H%M%S')"

deploy_params=(
    "--resource-group" "$RESOURCE_GROUP_NAME"
    "--name" "$deployment_name"
    "--template-file" "infra/main.bicep"
    "--parameters" "environmentName=$ENVIRONMENT_NAME"
    "--parameters" "location=$LOCATION"
    "--parameters" "searchIndexName=$SEARCH_INDEX_NAME"
)

if [[ -n "$API_KEY" ]]; then
    deploy_params+=("--parameters" "serverApiKey=$API_KEY")
fi

# Always pass APIM and VNet flags explicitly so Bicep gets the correct value
deploy_params+=("--parameters" "deployApim=$DEPLOY_APIM")
deploy_params+=("--parameters" "deployVNet=$DEPLOY_VNET")

if [[ "$DEPLOY_APIM" == "true" ]]; then
    deploy_params+=("--parameters" "apimPublisherEmail=$APIM_PUBLISHER_EMAIL")
    deploy_params+=("--parameters" "apimPublisherName=$APIM_PUBLISHER_NAME")
fi

if ! az deployment group create "${deploy_params[@]}" --output none; then
    echo "❌ Infrastructure deployment failed!"
    return 1
fi
echo "✅ Infrastructure deployed successfully"

# Get deployment outputs
echo ""
echo "Retrieving deployment information..."
# Normalize output keys to uppercase (Bicep/ARM mangles casing, e.g. AZURE → azurE)
outputs=$(az deployment group show \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$deployment_name" \
    --query "properties.outputs" \
    -o json | jq 'with_entries(.key |= ascii_upcase)')

acr_name=$(echo "$outputs" | jq -r '.AZURE_CONTAINER_REGISTRY_NAME.value')
acr_login_server=$(echo "$outputs" | jq -r '.AZURE_CONTAINER_REGISTRY_ENDPOINT.value')
search_endpoint=$(echo "$outputs" | jq -r '.SEARCH_ENDPOINT.value')
search_service_name=$(echo "$outputs" | jq -r '.SEARCH_SERVICE_NAME.value')
storage_account_name=$(echo "$outputs" | jq -r '.STORAGE_ACCOUNT_NAME.value')
storage_blob_endpoint=$(echo "$outputs" | jq -r '.STORAGE_BLOB_ENDPOINT.value')
openai_name=$(echo "$outputs" | jq -r '.AZURE_OPENAI_NAME.value')
openai_endpoint=$(echo "$outputs" | jq -r '.AZURE_OPENAI_ENDPOINT.value')
mcp_server_internal_uri=$(echo "$outputs" | jq -r '.MCP_SERVER_INTERNAL_URI.value')
mcp_public_endpoint=$(echo "$outputs" | jq -r '.MCP_PUBLIC_ENDPOINT.value')
generated_api_key=$(echo "$outputs" | jq -r '.MCP_SERVER_API_KEY.value')
managed_identity_name=$(echo "$outputs" | jq -r '.MANAGED_IDENTITY_NAME.value')
managed_identity_id=$(echo "$outputs" | jq -r '.MANAGED_IDENTITY_ID.value')
container_app_name=$(echo "$outputs" | jq -r '.CONTAINER_APP_NAME.value')
apim_gateway_url=$(echo "$outputs" | jq -r '.APIM_GATEWAY_URL.value // empty')
apim_name=$(echo "$outputs" | jq -r '.APIM_NAME.value // empty')
apim_subscription_key=$(echo "$outputs" | jq -r '.APIM_SUBSCRIPTION_KEY.value // empty')
storage_account_id=$(echo "$outputs" | jq -r '.STORAGE_ACCOUNT_ID.value')
ai_foundry_url=$(echo "$outputs" | jq -r '.AI_FOUNDRY_SERVICES_SUBDOMAIN_URL.value')
search_index_name=$(echo "$outputs" | jq -r '.SEARCH_INDEX_NAME.value')
subscription_id=$(echo "$outputs" | jq -r '.AZURE_SUBSCRIPTION_ID.value')
resource_group_out=$(echo "$outputs" | jq -r '.AZURE_RESOURCE_GROUP_NAME.value')

# Build and push container image
echo ""
echo "Building and pushing container image to ACR..."
image_name="mcp-azure-pdf"
full_image_name="${acr_login_server}/${image_name}:latest"

# Try local docker build + push first; fall back to az acr build (cloud-side build)
if az acr login --name "$acr_name" --output none 2>/dev/null; then
    if ! docker build -t "$full_image_name" . --quiet; then
        echo "❌ Docker build failed!"
        return 1
    fi
    if ! docker push "$full_image_name" --quiet; then
        echo "❌ Docker push failed!"
        return 1
    fi
else
    echo "⚠️  Local Docker push unavailable, using cloud build (az acr build)..."
    if ! az acr build --registry "$acr_name" --image "${image_name}:latest" . --no-logs; then
        echo "❌ ACR cloud build failed!"
        return 1
    fi
fi
echo "✅ Container image pushed successfully"

# Ensure the container app's ACR registry uses the managed identity
echo ""
echo "Ensuring ACR registry uses managed identity..."
if ! az containerapp registry set \
    --name "$container_app_name" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --server "$acr_login_server" \
    --identity "$managed_identity_id" \
    --output none; then
    echo "⚠️  Failed to set registry identity (may already be configured)"
fi
echo "✅ ACR registry identity configured"

# Update the container app to use the real ACR image
# (Bicep deploys with a placeholder image to avoid MANIFEST_UNKNOWN on first deploy)
echo ""
echo "Updating container app with the real image..."
if ! az containerapp update \
    --name "$container_app_name" \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --image "$full_image_name" \
    --output none; then
    echo "❌ Failed to update container app image!"
    return 1
fi
echo "✅ Container app updated with image: $full_image_name"

# Deploy search pipeline (data source, index, skillset, indexer) via REST API
echo ""
echo "Deploying AI search pipeline..."
export SEARCH_ENDPOINT="$search_endpoint"
export STORAGE_ACCOUNT_ID="$storage_account_id"
export STORAGE_ACCOUNT_NAME="$storage_account_name"
export AZURE_OPENAI_ENDPOINT="$openai_endpoint"
export AI_FOUNDRY_SERVICES_SUBDOMAIN_URL="$ai_foundry_url"
export AZURE_SUBSCRIPTION_ID="$subscription_id"
export AZURE_RESOURCE_GROUP_NAME="$resource_group_out"
export INDEX_NAME="$search_index_name"

if bash "$(dirname "$0")/setup-search-pipeline.sh"; then
    echo "✅ Search pipeline deployed"
else
    echo "⚠️  Search pipeline deployment had issues (non-fatal, can re-run setup-search-pipeline.sh)"
fi

# Display deployment summary
echo ""
echo "🎉 Deployment completed successfully!"
echo ""
echo "📋 Deployment Summary"
echo "====================="
echo "Resource Group:    $RESOURCE_GROUP_NAME"
echo "Location:          $LOCATION"
echo ""
echo "🌐 Public Access (Use This for Copilot)"
echo "  MCP API Endpoint: $mcp_public_endpoint"
if [[ -n "$apim_gateway_url" ]]; then
    echo "  APIM Gateway:     $apim_gateway_url"
    echo "  APIM Name:        $apim_name"
    if [[ -n "$apim_subscription_key" ]]; then
        echo "  Subscription Key: $apim_subscription_key"
        echo "  Auth Header:      Ocp-Apim-Subscription-Key: <key>"
    fi
fi
echo ""
echo "🔒 Security Architecture"
echo "  Container App:    Internal-only (no external access)"
echo "  Internal URL:     $mcp_server_internal_uri"
if [[ -n "$apim_gateway_url" ]]; then
    echo "  Traffic Flow:     Copilot → APIM Gateway → Container App → Azure Services"
    echo "  Authentication:   API Key (injected by APIM policy)"
else
    echo "  ⚠️ APIM:          Not deployed - using direct Container App access"
    echo "  ⚠️ Warning:       Container App is exposed externally without APIM!"
fi
echo ""
echo "🔍 Search Service"
echo "  Name:            $search_service_name"
echo "  Endpoint:        $search_endpoint"
echo "  Index:           $SEARCH_INDEX_NAME (needs to be created and populated)"
echo ""
echo "📦 Storage Account"
echo "  Name:            $storage_account_name"
echo "  Blob Endpoint:   $storage_blob_endpoint"
echo "  Containers:      pdfs, documents"
echo ""
echo "🤖 Azure OpenAI"
echo "  Name:            $openai_name"
echo "  Endpoint:        $openai_endpoint"
echo "  Deployments:     embeddings (text-embedding-3-large), chat (gpt-4o)"
echo ""
echo "🔐 Identity & Access"
echo "  Managed Identity: $managed_identity_name"
echo "  Role Assignments: Search Contributor, Storage Blob Contributor, OpenAI User, ACR Pull"
echo ""
echo "📝 Next Steps"
echo "============="
echo "1. Configure Copilot MCP Client:"
echo "   Update your mcp.json with:"
echo '   {'
echo '     "mcpServers": {'
echo '       "custom-pli-mcp": {'
echo "         \"url\": \"$mcp_public_endpoint\","
if [[ -n "$apim_subscription_key" ]]; then
echo "         \"headers\": { \"Ocp-Apim-Subscription-Key\": \"$apim_subscription_key\" }"
else
echo "         \"headers\": { \"x-api-key\": \"$generated_api_key\" }"
fi
echo '       }'
echo '     }'
echo '   }'
echo ""
echo "2. Upload PDF documents:"
echo "   az storage blob upload-batch -d pdfs -s <local-folder> --account-name $storage_account_name"
echo ""
echo "3. Test your deployment:"
if [[ -n "$apim_subscription_key" ]]; then
echo "   curl -H 'Ocp-Apim-Subscription-Key: $apim_subscription_key' $apim_gateway_url/mcp/health"
else
echo "   curl $mcp_public_endpoint/health"
fi
echo ""
echo "4. View logs and monitoring:"
echo "   az monitor log-analytics query --workspace <workspace-name> --analytics-query 'ContainerAppConsoleLogs_CL | top 100 by TimeGenerated'"
echo ""

}

main "$@"
