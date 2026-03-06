---
name: deployment-windows
description: Step-by-step deployment guide for the MCP Azure PDF Server on Windows using deploy.ps1 (PowerShell). Use this skill to walk through each deployment phase individually instead of running the monolithic script.
---

# Deployment — MCP Azure PDF Server on Windows (PowerShell)

## Overview

This skill breaks the `deploy.ps1` script into discrete, independently runnable steps. Use it when you need to deploy step-by-step, debug a specific phase, or resume a partially completed deployment on Windows.

## Prerequisites

- **Azure CLI** installed (`az --version`)
- **Docker Desktop** for Windows (running)
- **Node.js 20+** installed (`node --version`)
- **PowerShell 7+** recommended (works with Windows PowerShell 5.1)
- Azure CLI authenticated (`az login`)

## Deployment Parameters

```powershell
$EnvironmentName    = "mcp"
$ResourceGroupName  = "mcp-server-rg"
$Location           = "swedencentral"
$SearchIndexName    = "pdf-index"
$DeployApim         = $true
$DeployVNet         = $true
```

---

## Step 1: Verify Azure Authentication

```powershell
az account show --query "{user:user.name, subscription:name}" -o table
```

If not logged in:

```powershell
az login
```

## Step 2: Create Resource Group

```powershell
$rgExists = az group show --name $ResourceGroupName --query "name" -o tsv 2>$null
if (-not $rgExists) {
    az group create --name $ResourceGroupName --location $Location --output none
    Write-Host "✅ Resource group created" -ForegroundColor Green
} else {
    Write-Host "✅ Resource group exists" -ForegroundColor Green
}
```

## Step 3: Build the Project

```powershell
npm run build
if ($LASTEXITCODE -ne 0) { throw "Build failed!" }
Write-Host "✅ TypeScript compiled" -ForegroundColor Green
```

## Step 4: Deploy Infrastructure (Bicep)

This is the longest step (~5 min without APIM, ~20-30 min with APIM).

```powershell
$DeploymentName = "mcp-deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$deployParams = @(
    "--resource-group", $ResourceGroupName,
    "--name", $DeploymentName,
    "--template-file", "infra/main.bicep",
    "--parameters", "environmentName=$EnvironmentName",
    "--parameters", "location=$Location",
    "--parameters", "searchIndexName=$SearchIndexName",
    "--parameters", "deployApim=$($DeployApim.ToString().ToLower())",
    "--parameters", "deployVNet=$($DeployVNet.ToString().ToLower())"
)

az deployment group create @deployParams --output none
if ($LASTEXITCODE -ne 0) { throw "Infrastructure deployment failed!" }
Write-Host "✅ Infrastructure deployed" -ForegroundColor Green
```

**Optional**: Add `"--parameters", "serverApiKey=<key>"` for a custom API key.

## Step 5: Retrieve Deployment Outputs

```powershell
$outputs = az deployment group show `
    --resource-group $ResourceGroupName `
    --name $DeploymentName `
    --query "properties.outputs" -o json | ConvertFrom-Json

$acrName            = $outputs.AZURE_CONTAINER_REGISTRY_NAME.value
$acrLoginServer     = $outputs.AZURE_CONTAINER_REGISTRY_ENDPOINT.value
$containerAppName   = $outputs.CONTAINER_APP_NAME.value
$managedIdentityId  = $outputs.MANAGED_IDENTITY_ID.value
$searchEndpoint     = $outputs.SEARCH_ENDPOINT.value
$storageAccountName = $outputs.STORAGE_ACCOUNT_NAME.value
$aiFoundryEndpoint  = $outputs.AI_FOUNDRY_ENDPOINT.value
$mcpPublicEndpoint  = $outputs.MCP_PUBLIC_ENDPOINT.value
$apimName           = if ($outputs.APIM_NAME) { $outputs.APIM_NAME.value } else { "" }

Write-Host "ACR: $acrName ($acrLoginServer)"
Write-Host "Container App: $containerAppName"
Write-Host "Public endpoint: $mcpPublicEndpoint"
```

## Step 6: Retrieve Secrets at Runtime

Secrets are never stored in Bicep outputs. Retrieve them via CLI:

```powershell
# Server API key
$generatedApiKey = az containerapp secret show `
    --name $containerAppName `
    --resource-group $ResourceGroupName `
    --secret-name server-api-key `
    --query value -o tsv 2>$null
if (-not $generatedApiKey) { $generatedApiKey = '' }

# APIM subscription key (if APIM deployed)
$apimSubscriptionKey = ''
if ($apimName) {
    $apimId = az apim show --name $apimName --resource-group $ResourceGroupName --query id -o tsv 2>$null
    if ($apimId) {
        $apimSubscriptionKey = az rest --method POST `
            --url "$apimId/subscriptions/mcp-subscription/listSecrets?api-version=2023-05-01-preview" `
            --resource https://management.azure.com/ `
            --query primaryKey -o tsv 2>$null
        if (-not $apimSubscriptionKey) { $apimSubscriptionKey = '' }
    }
}

Write-Host "API Key: $generatedApiKey"
Write-Host "APIM Key: $apimSubscriptionKey"
```

## Step 7: Build and Push Docker Image

```powershell
$imageName = "mcp-azure-pdf"
$fullImage = "$acrLoginServer/$($imageName):latest"

# Login to ACR
az acr login --name $acrName --output none

# Build and push
docker build -t $fullImage . --quiet
if ($LASTEXITCODE -ne 0) { throw "Docker build failed!" }

docker push $fullImage --quiet
if ($LASTEXITCODE -ne 0) { throw "Docker push failed!" }

Write-Host "✅ Image pushed: $fullImage" -ForegroundColor Green
```

### Fallback: Cloud Build

If local Docker is unavailable:

```powershell
az acr build --registry $acrName --image "$($imageName):latest" . --no-logs
if ($LASTEXITCODE -ne 0) { throw "ACR cloud build failed!" }
Write-Host "✅ Image built in cloud" -ForegroundColor Green
```

## Step 8: Configure Container App

```powershell
# Set ACR managed identity
az containerapp registry set `
    --name $containerAppName `
    --resource-group $ResourceGroupName `
    --server $acrLoginServer `
    --identity $managedIdentityId `
    --output none

# Update to real image (Bicep deploys a placeholder)
az containerapp update `
    --name $containerAppName `
    --resource-group $ResourceGroupName `
    --image $fullImage `
    --output none

Write-Host "✅ Container App updated" -ForegroundColor Green
```

## Step 9: Deploy Search Pipeline

```powershell
$env:SEARCH_ENDPOINT              = $searchEndpoint
$env:STORAGE_ACCOUNT_ID           = $outputs.STORAGE_ACCOUNT_ID.value
$env:STORAGE_ACCOUNT_NAME         = $storageAccountName
$env:AI_FOUNDRY_ENDPOINT           = $aiFoundryEndpoint
$env:AI_FOUNDRY_SERVICES_SUBDOMAIN_URL = $outputs.AI_FOUNDRY_SERVICES_SUBDOMAIN_URL.value
$env:AZURE_SUBSCRIPTION_ID        = $outputs.AZURE_SUBSCRIPTION_ID.value
$env:AZURE_RESOURCE_GROUP_NAME    = $outputs.AZURE_RESOURCE_GROUP_NAME.value
$env:INDEX_NAME                   = $SearchIndexName

& .\setup-search-pipeline.ps1
Write-Host "✅ Search pipeline deployed" -ForegroundColor Green
```

## Step 10: Validate Deployment

```powershell
# Health check
Invoke-RestMethod -Uri "$mcpPublicEndpoint/health" | ConvertTo-Json

# Search test (via APIM)
$body = @{ query = "test"; top = 3 } | ConvertTo-Json
$headers = @{ "Content-Type" = "application/json"; "Ocp-Apim-Subscription-Key" = $apimSubscriptionKey }
$result = Invoke-RestMethod -Uri "$mcpPublicEndpoint/api/search" -Method POST -Body $body -Headers $headers
Write-Host "Results: $($result.results.Count)"
```

Or run the validation script:

```powershell
.\validate-deployment.ps1 -ResourceGroupName $ResourceGroupName
```

## Step 11: Upload PDFs (Post-Deployment)

```powershell
az storage blob upload-batch `
    -d pdfs `
    -s .\my-pdfs `
    --account-name $storageAccountName `
    --auth-mode login
```

After uploading, the indexer will automatically pick up new documents. To trigger manually:

```powershell
$token = az account get-access-token --resource https://search.azure.com/ --query accessToken -o tsv
$headers = @{ "Authorization" = "Bearer $token" }
Invoke-RestMethod -Uri "$searchEndpoint/indexers/pdf-indexer/run?api-version=2025-11-01-Preview" `
    -Method POST -Headers $headers
```

---

## One-Command Deployment

To run all steps at once:

```powershell
.\deploy.ps1
```

Or with custom parameters:

```powershell
.\deploy.ps1 `
    -ResourceGroupName "my-mcp-rg" `
    -Location "eastus" `
    -EnvironmentName "prod" `
    -DeployApim $true `
    -DeployVNet $true
```

## Common Issues

| Problem | Solution |
|---------|----------|
| Bicep deployment fails with "name in use" | Soft-deleted resources block names. Run `.\cleanup.ps1 -PurgeAll -Yes` first |
| Docker Desktop not running | Start Docker Desktop from Windows Start menu |
| APIM takes 20-30 minutes | Normal for first deployment. Use `-DeployApim $false` to skip during development |
| `MANIFEST_UNKNOWN` on container start | The placeholder image hasn't been replaced yet. Complete Step 8 |
| Search returns 0 results | Upload PDFs (Step 11) and wait for indexer to run |
| `Invoke-RestMethod` SSL errors | Ensure TLS 1.2: `[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12` |
| PowerShell execution policy | Run `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser` |
