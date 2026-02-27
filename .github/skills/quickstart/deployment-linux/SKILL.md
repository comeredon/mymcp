---
name: deployment-linux
description: Step-by-step deployment guide for the MCP Azure PDF Server on Linux / WSL2 using deploy.sh. Use this skill to walk through each deployment phase individually instead of running the monolithic script.
---

# Deployment — MCP Azure PDF Server on Linux / WSL2

## Overview

This skill breaks the `deploy.sh` script into discrete, independently runnable steps. Use it when you need to deploy step-by-step, debug a specific phase, or resume a partially completed deployment.

## Prerequisites

- All tools installed (see `quickstart/wsl2-environment-setup` skill)
- Azure CLI authenticated (`az login`)
- Docker running (Docker Desktop WSL2 integration or native Docker Engine)
- `jq` installed

## Deployment Parameters

Set these environment variables or pass as arguments to `deploy.sh`:

```bash
export ENVIRONMENT_NAME="mcp"
export RESOURCE_GROUP_NAME="mcp-server-rg"
export LOCATION="swedencentral"
export SEARCH_INDEX_NAME="pdf-index"
export DEPLOY_APIM="true"
export DEPLOY_VNET="true"
```

---

## Step 1: Verify Azure Authentication

```bash
az account show --query "{user:user.name, subscription:name}" -o table
```

If not logged in:

```bash
az login
# Or in WSL2 if browser doesn't open:
az login --use-device-code
```

## Step 2: Create Resource Group

```bash
RESOURCE_GROUP_NAME="mcp-server-rg"
LOCATION="swedencentral"

az group show --name "$RESOURCE_GROUP_NAME" --query "name" -o tsv 2>/dev/null \
  || az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION" --output none

echo "✅ Resource group ready"
```

## Step 3: Build the Project

```bash
npm run build
echo "✅ TypeScript compiled"
```

Optionally verify with type checking:

```bash
npx tsc --noEmit
```

## Step 4: Deploy Infrastructure (Bicep)

This is the longest step (~5 min without APIM, ~20-30 min with APIM).

```bash
DEPLOYMENT_NAME="mcp-deploy-$(date '+%Y%m%d-%H%M%S')"

az deployment group create \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --name "$DEPLOYMENT_NAME" \
  --template-file infra/main.bicep \
  --parameters environmentName="$ENVIRONMENT_NAME" \
  --parameters location="$LOCATION" \
  --parameters searchIndexName="$SEARCH_INDEX_NAME" \
  --parameters deployApim="$DEPLOY_APIM" \
  --parameters deployVNet="$DEPLOY_VNET" \
  --output none

echo "✅ Infrastructure deployed"
```

**Optional parameters**: `--parameters serverApiKey=<key>` to set a custom API key.

## Step 5: Retrieve Deployment Outputs

```bash
# Normalize keys to uppercase (Bicep/ARM may mangle casing)
outputs=$(az deployment group show \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --name "$DEPLOYMENT_NAME" \
  --query "properties.outputs" -o json | jq 'with_entries(.key |= ascii_upcase)')

# Extract values
acr_name=$(echo "$outputs" | jq -r '.AZURE_CONTAINER_REGISTRY_NAME.value')
acr_login_server=$(echo "$outputs" | jq -r '.AZURE_CONTAINER_REGISTRY_ENDPOINT.value')
container_app_name=$(echo "$outputs" | jq -r '.CONTAINER_APP_NAME.value')
managed_identity_id=$(echo "$outputs" | jq -r '.MANAGED_IDENTITY_ID.value')
search_endpoint=$(echo "$outputs" | jq -r '.SEARCH_ENDPOINT.value')
storage_account_name=$(echo "$outputs" | jq -r '.STORAGE_ACCOUNT_NAME.value')
openai_endpoint=$(echo "$outputs" | jq -r '.AZURE_OPENAI_ENDPOINT.value')
mcp_public_endpoint=$(echo "$outputs" | jq -r '.MCP_PUBLIC_ENDPOINT.value')
apim_name=$(echo "$outputs" | jq -r '.APIM_NAME.value // empty')

echo "ACR: $acr_name ($acr_login_server)"
echo "Container App: $container_app_name"
echo "Public endpoint: $mcp_public_endpoint"
```

## Step 6: Retrieve Secrets at Runtime

Secrets are never stored in Bicep outputs. Retrieve them via CLI:

```bash
# Server API key
generated_api_key=$(az containerapp secret show \
  --name "$container_app_name" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --secret-name server-api-key \
  --query value -o tsv 2>/dev/null || echo '')

# APIM subscription key (if APIM deployed)
apim_subscription_key=''
if [[ -n "$apim_name" ]]; then
  apim_id=$(az apim show --name "$apim_name" --resource-group "$RESOURCE_GROUP_NAME" --query id -o tsv)
  apim_subscription_key=$(az rest --method POST \
    --url "${apim_id}/subscriptions/mcp-subscription/listSecrets?api-version=2023-05-01-preview" \
    --resource https://management.azure.com/ \
    --query primaryKey -o tsv 2>/dev/null || echo '')
fi

echo "API Key: $generated_api_key"
echo "APIM Key: $apim_subscription_key"
```

## Step 7: Build and Push Docker Image

```bash
image_name="mcp-azure-pdf"
full_image="$acr_login_server/$image_name:latest"

# Login to ACR
az acr login --name "$acr_name" --output none 2>/dev/null

# Build and push
docker build -t "$full_image" . --quiet
docker push "$full_image" --quiet

echo "✅ Image pushed: $full_image"
```

### WSL2 Docker Credential Fix

If `docker push` fails with `docker-credential-desktop.exe: not found`:

```bash
echo '{"credsStore":""}' > ~/.docker/config.json
TOKEN=$(az acr login --name "$acr_name" --expose-token --query accessToken -o tsv)
docker login "$acr_login_server" -u 00000000-0000-0000-0000-000000000000 --password-stdin <<< "$TOKEN"
# Then retry docker push
```

### Fallback: Cloud Build

If local Docker is unavailable:

```bash
az acr build --registry "$acr_name" --image "$image_name:latest" . --no-logs
echo "✅ Image built in cloud"
```

## Step 8: Configure Container App

```bash
# Set ACR managed identity
az containerapp registry set \
  --name "$container_app_name" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --server "$acr_login_server" \
  --identity "$managed_identity_id" \
  --output none

# Update to real image (Bicep deploys a placeholder)
az containerapp update \
  --name "$container_app_name" \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --image "$full_image" \
  --output none

echo "✅ Container App updated"
```

## Step 9: Deploy Search Pipeline

```bash
export SEARCH_ENDPOINT="$search_endpoint"
export STORAGE_ACCOUNT_ID=$(echo "$outputs" | jq -r '.STORAGE_ACCOUNT_ID.value')
export STORAGE_ACCOUNT_NAME="$storage_account_name"
export AZURE_OPENAI_ENDPOINT="$openai_endpoint"
export AI_FOUNDRY_SERVICES_SUBDOMAIN_URL=$(echo "$outputs" | jq -r '.AI_FOUNDRY_SERVICES_SUBDOMAIN_URL.value')
export AZURE_SUBSCRIPTION_ID=$(echo "$outputs" | jq -r '.AZURE_SUBSCRIPTION_ID.value')
export AZURE_RESOURCE_GROUP_NAME=$(echo "$outputs" | jq -r '.AZURE_RESOURCE_GROUP_NAME.value')
export INDEX_NAME="$SEARCH_INDEX_NAME"

bash setup-search-pipeline.sh
echo "✅ Search pipeline deployed"
```

## Step 10: Validate Deployment

```bash
# Health check
curl -s "$mcp_public_endpoint/health" | jq .

# Search test (via APIM)
curl -s -X POST "$mcp_public_endpoint/api/search" \
  -H "Content-Type: application/json" \
  -H "Ocp-Apim-Subscription-Key: $apim_subscription_key" \
  -d '{"query": "test", "top": 3}' | jq '.results | length'
```

Or run the validation script:

```bash
bash validate-deployment.sh --resource-group "$RESOURCE_GROUP_NAME"
```

## Step 11: Upload PDFs (Post-Deployment)

```bash
az storage blob upload-batch \
  -d pdfs \
  -s ./my-pdfs \
  --account-name "$storage_account_name" \
  --auth-mode login
```

After uploading, the indexer will automatically pick up new documents. To trigger manually:

```bash
TOKEN=$(az account get-access-token --resource https://search.azure.com/ --query accessToken -o tsv)
curl -X POST "$search_endpoint/indexers/pdf-indexer/run?api-version=2025-05-01-Preview" \
  -H "Authorization: Bearer $TOKEN"
```

---

## One-Command Deployment

To run all steps at once:

```bash
bash deploy.sh --deploy-apim --deploy-vnet
```

Or with custom parameters:

```bash
bash deploy.sh \
  --resource-group "my-mcp-rg" \
  --location "eastus" \
  --environment-name "prod" \
  --deploy-apim
```

## Common Issues

| Problem | Solution |
|---------|----------|
| Bicep deployment fails with "name in use" | Soft-deleted resources block names. Run `cleanup.sh --purge-all --yes` first |
| `docker-credential-desktop.exe: not found` | See WSL2 Docker Credential Fix in Step 7 |
| APIM takes 20-30 minutes | Normal for first deployment. Use `--no-apim` to skip during development |
| `MANIFEST_UNKNOWN` on container start | The placeholder image hasn't been replaced yet. Complete Step 8 |
| Search returns 0 results | Upload PDFs (Step 11) and wait for indexer to run |
| `disableLocalAuth` errors | Search uses RBAC only. Use `az account get-access-token --resource https://search.azure.com/` |
