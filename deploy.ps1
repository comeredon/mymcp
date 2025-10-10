# MCP Azure PDF Server - Unified Deployment Script
# Deploys all required Azure resources and the MCP server container

param(
    [string]$EnvironmentName = "mcp",
    [string]$ResourceGroupName = "mcp-server-rg",
    [string]$Location = "swedencentral",
    [string]$SearchIndexName = "pdf-index",
    [string]$ApiKey = ""
)

Write-Host "🚀 MCP Azure PDF Server - Unified Deployment" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Check if logged in to Azure
Write-Host "Checking Azure authentication..." -ForegroundColor Yellow
$loginStatus = az account show --query "user.name" -o tsv 2>$null
if (-not $loginStatus) {
    Write-Host "❌ Not logged in to Azure" -ForegroundColor Red
    Write-Host "Please run: az login" -ForegroundColor Yellow
    exit 1
}
Write-Host "✅ Logged in as: $loginStatus" -ForegroundColor Green

# Create resource group if it doesn't exist
Write-Host "`nChecking resource group '$ResourceGroupName'..." -ForegroundColor Yellow
$rgExists = az group show --name $ResourceGroupName --query "name" -o tsv 2>$null
if (-not $rgExists) {
    Write-Host "Creating resource group '$ResourceGroupName' in '$Location'..." -ForegroundColor Yellow
    az group create --name $ResourceGroupName --location $Location --output none
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to create resource group" -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ Resource group created" -ForegroundColor Green
} else {
    Write-Host "✅ Resource group exists" -ForegroundColor Green
}

# Build the project
Write-Host "`nBuilding the project..." -ForegroundColor Yellow
npm run build
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Build failed!" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Build completed" -ForegroundColor Green

# Deploy infrastructure
Write-Host "`nDeploying Azure infrastructure..." -ForegroundColor Yellow
Write-Host "This will create:" -ForegroundColor Cyan
Write-Host "  - Azure AI Search service" -ForegroundColor White
Write-Host "  - Container Apps Environment" -ForegroundColor White
Write-Host "  - Container Registry" -ForegroundColor White
Write-Host "  - Log Analytics Workspace" -ForegroundColor White
Write-Host "  - MCP Server Container App" -ForegroundColor White
Write-Host ""

$deploymentName = "mcp-deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$deployParams = @(
    "--resource-group", $ResourceGroupName,
    "--name", $deploymentName,
    "--template-file", "infra/main.bicep",
    "--parameters", "environmentName=$EnvironmentName",
    "--parameters", "location=$Location",
    "--parameters", "searchIndexName=$SearchIndexName"
)

if (-not [string]::IsNullOrEmpty($ApiKey)) {
    $deployParams += "--parameters"
    $deployParams += "serverApiKey=$ApiKey"
}

az deployment group create @deployParams --output none

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Infrastructure deployment failed!" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Infrastructure deployed successfully" -ForegroundColor Green

# Get deployment outputs
Write-Host "`nRetrieving deployment information..." -ForegroundColor Yellow
$outputs = az deployment group show `
    --resource-group $ResourceGroupName `
    --name $deploymentName `
    --query "properties.outputs" `
    -o json | ConvertFrom-Json

$acrName = $outputs.AZURE_CONTAINER_REGISTRY_NAME.value
$acrLoginServer = $outputs.AZURE_CONTAINER_REGISTRY_ENDPOINT.value
$searchEndpoint = $outputs.SEARCH_ENDPOINT.value
$searchServiceName = $outputs.SEARCH_SERVICE_NAME.value
$mcpServerUri = $outputs.MCP_SERVER_URI.value
$generatedApiKey = $outputs.MCP_SERVER_API_KEY.value

# Build and push container image
Write-Host "`nBuilding Docker image..." -ForegroundColor Yellow
$imageName = "mcp-azure-pdf"
$fullImageName = "$acrLoginServer/${imageName}:latest"

docker build -t $fullImageName . --quiet
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Docker build failed!" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Docker image built" -ForegroundColor Green

# Login to ACR and push
Write-Host "`nPushing image to Azure Container Registry..." -ForegroundColor Yellow
az acr login --name $acrName --output none
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ ACR login failed!" -ForegroundColor Red
    exit 1
}

docker push $fullImageName --quiet
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Docker push failed!" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Container image pushed successfully" -ForegroundColor Green

# Display deployment summary
Write-Host ""
Write-Host "🎉 Deployment completed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "📋 Deployment Summary" -ForegroundColor Cyan
Write-Host "=====================" -ForegroundColor Cyan
Write-Host "Resource Group:    $ResourceGroupName" -ForegroundColor White
Write-Host "Location:          $Location" -ForegroundColor White
Write-Host ""
Write-Host "Search Service:    $searchServiceName" -ForegroundColor White
Write-Host "Search Endpoint:   $searchEndpoint" -ForegroundColor White
Write-Host "Search Index:      $SearchIndexName (needs to be created and populated)" -ForegroundColor Yellow
Write-Host ""
Write-Host "MCP Server URL:    $mcpServerUri" -ForegroundColor White
Write-Host "API Key:           $generatedApiKey" -ForegroundColor White
Write-Host ""
Write-Host "📝 Next Steps" -ForegroundColor Cyan
Write-Host "=============" -ForegroundColor Cyan
Write-Host "1. Index your PDF documents in Azure AI Search:" -ForegroundColor White
Write-Host "   - Go to Azure Portal → Search Service: $searchServiceName" -ForegroundColor White
Write-Host "   - Create index '$SearchIndexName' with your PDF content" -ForegroundColor White
Write-Host "   - Use Azure AI Document Intelligence or custom indexing" -ForegroundColor White
Write-Host ""
Write-Host "2. Test your deployment:" -ForegroundColor White
Write-Host "   Health check: curl $mcpServerUri/health" -ForegroundColor White
Write-Host ""
Write-Host "3. Use the MCP server:" -ForegroundColor White
Write-Host "   Set MCP_SERVER_URL=$mcpServerUri/api/tools" -ForegroundColor White
Write-Host "   Use API Key: $generatedApiKey" -ForegroundColor White
Write-Host ""