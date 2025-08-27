# Deploy MCP Server to Existing Resource Group
# This script deploys the MCP server to your existing 'mcpserver' resource group in swedencentral

param(
    [string]$EnvironmentName = "dev",
    [string]$ResourceGroupName = "mcpserver",
    [string]$Location = "swedencentral"
)

Write-Host "🚀 Deploying MCP Server to existing resource group: $ResourceGroupName" -ForegroundColor Green

# Set environment variables for AZD
$env:AZURE_ENV_NAME = $EnvironmentName
$env:AZURE_LOCATION = $Location
$env:AZURE_RESOURCE_GROUP = $ResourceGroupName

# Check if logged in to Azure
Write-Host "Checking Azure login status..." -ForegroundColor Yellow
$loginStatus = az account show --query "user.name" -o tsv 2>$null
if (-not $loginStatus) {
    Write-Host "Please login to Azure first:" -ForegroundColor Red
    Write-Host "az login" -ForegroundColor Cyan
    exit 1
}

Write-Host "✅ Logged in as: $loginStatus" -ForegroundColor Green

# Check if resource group exists
Write-Host "Checking if resource group '$ResourceGroupName' exists..." -ForegroundColor Yellow
$rgExists = az group show --name $ResourceGroupName --query "name" -o tsv 2>$null
if (-not $rgExists) {
    Write-Host "❌ Resource group '$ResourceGroupName' not found!" -ForegroundColor Red
    Write-Host "Please create it first or check the name." -ForegroundColor Red
    exit 1
}

Write-Host "✅ Resource group '$ResourceGroupName' found" -ForegroundColor Green

# Get current user ID for role assignments
Write-Host "Getting current user principal ID..." -ForegroundColor Yellow
$principalId = az ad signed-in-user show --query "id" -o tsv
if (-not $principalId) {
    Write-Host "❌ Could not get user principal ID" -ForegroundColor Red
    exit 1
}

Write-Host "✅ User principal ID: $principalId" -ForegroundColor Green

# Build the project
Write-Host "Building the project..." -ForegroundColor Yellow
npm run build
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Build failed!" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Build completed" -ForegroundColor Green

# Deploy using Azure CLI instead of AZD since we're targeting an existing RG
Write-Host "Deploying infrastructure to resource group..." -ForegroundColor Yellow

$deploymentName = "mcp-server-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

az deployment group create `
    --resource-group $ResourceGroupName `
    --name $deploymentName `
    --template-file "infra/main.bicep" `
    --parameters environmentName=$EnvironmentName `
    --parameters location=$Location `
    --parameters principalId=$principalId

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Infrastructure deployment failed!" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Infrastructure deployed successfully" -ForegroundColor Green

# Get deployment outputs
Write-Host "Getting deployment outputs..." -ForegroundColor Yellow
$outputs = az deployment group show --resource-group $ResourceGroupName --name $deploymentName --query "properties.outputs" -o json | ConvertFrom-Json

$acrName = $outputs.AZURE_CONTAINER_REGISTRY_NAME.value
$acrLoginServer = $outputs.AZURE_CONTAINER_REGISTRY_ENDPOINT.value
$mcpServerUri = $outputs.MCP_SERVER_URI.value
$apiKey = $outputs.MCP_SERVER_API_KEY.value

Write-Host "📋 Deployment Summary:" -ForegroundColor Cyan
Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor White
Write-Host "  Location: $Location" -ForegroundColor White
Write-Host "  Container Registry: $acrName" -ForegroundColor White
Write-Host "  MCP Server URL: $mcpServerUri" -ForegroundColor White
Write-Host "  API Key: $apiKey" -ForegroundColor White

# Build and push container image
Write-Host "Building and pushing container image..." -ForegroundColor Yellow

# Login to ACR
az acr login --name $acrName

# Build and push image
$imageName = "mcp-azure-pdf"
$fullImageName = "$acrLoginServer/${imageName}:latest"

docker build -t $fullImageName .
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Docker build failed!" -ForegroundColor Red
    exit 1
}

docker push $fullImageName
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Docker push failed!" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Container image pushed successfully" -ForegroundColor Green

Write-Host "🎉 Deployment completed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Create an AI Search index called 'pdf-index' and populate it with your PDF documents" -ForegroundColor White
Write-Host "2. Test your MCP server at: $mcpServerUri" -ForegroundColor White
Write-Host "3. Use API Key: $apiKey" -ForegroundColor White
Write-Host "4. Health check endpoint: $mcpServerUri/health" -ForegroundColor White