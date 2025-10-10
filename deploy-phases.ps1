# Fixed Deployment Script - Deploy in Two Phases

param(
    [switch]$DryRun = $false
)

# Include common functions
. "$PSScriptRoot/common-functions.ps1"

Write-Info "🚀 MCP Azure PDF Server - Two-Phase Deployment"
Write-Info "==========================================="

# Phase 1: Deploy Infrastructure (excluding Container App)
Write-Info "Phase 1: Deploying infrastructure..."

# Read environment variables
$envFile = ".env.local"
if (!(Test-Path $envFile)) {
    Write-Error "Environment file $envFile not found. Please run validate-env.ps1 first."
    exit 1
}

$envVars = @{}
Get-Content $envFile | ForEach-Object {
    if ($_ -match "^(.+)=(.*)$") {
        $envVars[$matches[1]] = $matches[2]
    }
}

# Get resource group from environment or use default
$resourceGroup = if ($envVars.ContainsKey('AZURE_RESOURCE_GROUP')) { $envVars['AZURE_RESOURCE_GROUP'] } else { "mcpserver" }
$environmentName = if ($envVars.ContainsKey('AZURE_ENV_NAME')) { $envVars['AZURE_ENV_NAME'] } else { "mcp-pdf" }

Write-Info "Using Resource Group: $resourceGroup"
Write-Info "Using Environment Name: $environmentName"

# Deploy container registry and environment only
Write-Info "Deploying Container Registry and Environment..."
$infraResult = az deployment group create `
    --resource-group $resourceGroup `
    --template-file "infra/phase1-infra.bicep" `
    --parameters environmentName=$environmentName `
    --query "properties.outputs" `
    --output json

if ($LASTEXITCODE -ne 0) {
    Write-Error "Phase 1 infrastructure deployment failed"
    exit 1
}

$infraOutputs = $infraResult | ConvertFrom-Json
$acrName = $infraOutputs.containerRegistryName.value
$acrLoginServer = $infraOutputs.containerRegistryLoginServer.value

# Phase 2: Build and Push Container
Write-Info "Phase 2: Building and pushing container..."

# Build Docker image
Write-Info "Building Docker image..."
docker build -t mcp-azure-pdf .

if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker build failed"
    exit 1
}

# Login to ACR and push
Write-Info "Pushing to Azure Container Registry..."
az acr login --name $acrName

docker tag mcp-azure-pdf "$acrLoginServer/mcp-azure-pdf:latest"
docker push "$acrLoginServer/mcp-azure-pdf:latest"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker push failed"
    exit 1
}

# Phase 3: Deploy Container App
Write-Info "Phase 3: Deploying Container App..."

# Validate required environment variables
if (!$envVars.ContainsKey('SEARCH_ENDPOINT')) {
    Write-Error "SEARCH_ENDPOINT is required in .env.local"
    exit 1
}
if (!$envVars.ContainsKey('SEARCH_KEY')) {
    Write-Error "SEARCH_KEY is required in .env.local"
    exit 1
}
if (!$envVars.ContainsKey('SEARCH_INDEX')) {
    Write-Error "SEARCH_INDEX is required in .env.local"
    exit 1
}
if (!$envVars.ContainsKey('SERVER_API_KEY')) {
    Write-Error "SERVER_API_KEY is required in .env.local"
    exit 1
}

# Extract search service name from endpoint
$searchServiceName = ""
if ($envVars['SEARCH_ENDPOINT'] -match "https://([^.]+)\.search\.windows\.net") {
    $searchServiceName = $matches[1]
} else {
    Write-Error "Invalid SEARCH_ENDPOINT format. Expected: https://your-service.search.windows.net/"
    exit 1
}

$appResult = az deployment group create `
    --resource-group $resourceGroup `
    --template-file "infra/phase2-app.bicep" `
    --parameters environmentName=$environmentName `
    --parameters searchServiceName="$searchServiceName" `
    --parameters searchIndexName="$($envVars['SEARCH_INDEX'])" `
    --parameters searchEndpoint="$($envVars['SEARCH_ENDPOINT'])" `
    --parameters searchKey="$($envVars['SEARCH_KEY'])" `
    --parameters serverApiKey="$($envVars['SERVER_API_KEY'])" `
    --query "properties.outputs" `
    --output json

if ($LASTEXITCODE -ne 0) {
    Write-Error "Container App deployment failed"
    exit 1
}

$appOutputs = $appResult | ConvertFrom-Json
$containerAppUrl = $appOutputs.containerAppUrl.value

Write-Success "🎉 Deployment completed successfully!"
Write-Info "Container App URL: $containerAppUrl"
Write-Info "Health Check: $containerAppUrl/health"
Write-Info "API Docs: $containerAppUrl/docs"