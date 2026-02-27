# MCP Azure PDF Server - Unified Deployment Script
# Deploys all required Azure resources and the MCP server container

param(
    [string]$EnvironmentName = "mcp",
    [string]$ResourceGroupName = "mcp-server-rg",
    [string]$Location = "swedencentral",
    [string]$SearchIndexName = "pdf-index",
    [string]$ApiKey = "",
    [switch]$DeployApim = $false,
    [string]$ApimPublisherEmail = "admin@contoso.com",
    [string]$ApimPublisherName = "Contoso",
    [switch]$DeployVNet = $false
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
Write-Host "  - Storage Account (for PDF documents)" -ForegroundColor White
Write-Host "  - Azure OpenAI (with embeddings & chat models)" -ForegroundColor White
Write-Host "  - Container Apps Environment" -ForegroundColor White
Write-Host "  - Container Registry" -ForegroundColor White
Write-Host "  - Log Analytics Workspace" -ForegroundColor White
Write-Host "  - Managed Identity (with RBAC roles)" -ForegroundColor White
Write-Host "  - MCP Server Container App" -ForegroundColor White
if ($DeployApim) {
    Write-Host "  - API Management" -ForegroundColor White
}
if ($DeployVNet) {
    Write-Host "  - Virtual Network" -ForegroundColor White
}
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

if ($DeployApim) {
    $deployParams += "--parameters"
    $deployParams += "deployApim=true"
    $deployParams += "--parameters"
    $deployParams += "apimPublisherEmail=$ApimPublisherEmail"
    $deployParams += "--parameters"
    $deployParams += "apimPublisherName=$ApimPublisherName"
}

if ($DeployVNet) {
    $deployParams += "--parameters"
    $deployParams += "deployVNet=true"
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
$storageAccountName = $outputs.STORAGE_ACCOUNT_NAME.value
$storageBlobEndpoint = $outputs.STORAGE_BLOB_ENDPOINT.value
$openAiName = $outputs.AZURE_OPENAI_NAME.value
$openAiEndpoint = $outputs.AZURE_OPENAI_ENDPOINT.value
$mcpServerInternalUri = $outputs.MCP_SERVER_INTERNAL_URI.value
$mcpPublicEndpoint = $outputs.MCP_PUBLIC_ENDPOINT.value
$generatedApiKey = $outputs.MCP_SERVER_API_KEY.value
$managedIdentityName = $outputs.MANAGED_IDENTITY_NAME.value
$apimGatewayUrl = if ($outputs.APIM_GATEWAY_URL) { $outputs.APIM_GATEWAY_URL.value } else { "" }
$apimName = if ($outputs.APIM_NAME) { $outputs.APIM_NAME.value } else { "" }

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
Write-Host "🌐 Public Access (Use This for Copilot)" -ForegroundColor Green
Write-Host "  MCP API Endpoint: $mcpPublicEndpoint" -ForegroundColor White
if ($apimGatewayUrl) {
    Write-Host "  APIM Gateway:     $apimGatewayUrl" -ForegroundColor White
    Write-Host "  APIM Name:        $apimName" -ForegroundColor White
}
Write-Host ""
Write-Host "🔒 Security Architecture" -ForegroundColor Cyan
Write-Host "  Container App:    Internal-only (no external access)" -ForegroundColor White
Write-Host "  Internal URL:     $mcpServerInternalUri" -ForegroundColor Gray
if ($apimGatewayUrl) {
    Write-Host "  Traffic Flow:     Copilot → APIM Gateway → Container App → Azure Services" -ForegroundColor White
    Write-Host "  Authentication:   API Key (injected by APIM policy)" -ForegroundColor White
} else {
    Write-Host "  ⚠️ APIM:          Not deployed - using direct Container App access" -ForegroundColor Yellow
    Write-Host "  ⚠️ Warning:       Container App is exposed externally without APIM!" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "🔍 Search Service" -ForegroundColor Cyan
Write-Host "  Name:            $searchServiceName" -ForegroundColor White
Write-Host "  Endpoint:        $searchEndpoint" -ForegroundColor White
Write-Host "  Index:           $SearchIndexName (needs to be created and populated)" -ForegroundColor Yellow
Write-Host ""
Write-Host "📦 Storage Account" -ForegroundColor Cyan
Write-Host "  Name:            $storageAccountName" -ForegroundColor White
Write-Host "  Blob Endpoint:   $storageBlobEndpoint" -ForegroundColor White
Write-Host "  Containers:      pdfs, documents" -ForegroundColor White
Write-Host ""
Write-Host "🤖 Azure OpenAI" -ForegroundColor Cyan
Write-Host "  Name:            $openAiName" -ForegroundColor White
Write-Host "  Endpoint:        $openAiEndpoint" -ForegroundColor White
Write-Host "  Deployments:     embeddings (text-embedding-ada-002), chat (gpt-4o)" -ForegroundColor White
Write-Host ""
Write-Host "🔐 Identity & Access" -ForegroundColor Cyan
Write-Host "  Managed Identity: $managedIdentityName" -ForegroundColor White
Write-Host "  Role Assignments: Search Contributor, Storage Blob Contributor, OpenAI User, ACR Pull" -ForegroundColor White
Write-Host ""
Write-Host "📝 Next Steps" -ForegroundColor Cyan
Write-Host "=============" -ForegroundColor Cyan
Write-Host "1. Configure Copilot MCP Client:" -ForegroundColor White
Write-Host "   Update your mcp.json with:" -ForegroundColor White
Write-Host "   {" -ForegroundColor Gray
Write-Host "     `"mcpServers`": {" -ForegroundColor Gray
Write-Host "       `"custom-pli-mc`": {" -ForegroundColor Gray
Write-Host "         `"url`": `"$mcpPublicEndpoint`"" -ForegroundColor Gray
Write-Host "       }" -ForegroundColor Gray
Write-Host "     }" -ForegroundColor Gray
Write-Host "   }" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Upload PDF documents:" -ForegroundColor White
Write-Host "   az storage blob upload-batch -d pdfs -s <local-folder> --account-name $storageAccountName" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Index your PDF documents in Azure AI Search:" -ForegroundColor White
Write-Host "   - Go to Azure Portal → Search Service: $searchServiceName" -ForegroundColor White
Write-Host "   - Create index '$SearchIndexName' with your PDF content" -ForegroundColor White
Write-Host "   - Use Azure AI Document Intelligence or custom indexing" -ForegroundColor White
Write-Host ""
Write-Host "4. Test your deployment:" -ForegroundColor White
Write-Host "   curl $mcpPublicEndpoint/health" -ForegroundColor Gray
Write-Host ""
Write-Host "5. View logs and monitoring:" -ForegroundColor White
Write-Host "   az monitor log-analytics query --workspace $logAnalyticsWorkspaceName --analytics-query 'ContainerAppConsoleLogs_CL | top 100 by TimeGenerated'" -ForegroundColor Gray
Write-Host ""
Write-Host "4. Configure your MCP client (GitHub Copilot):" -ForegroundColor White
Write-Host "   Update mcp.json with:" -ForegroundColor White
Write-Host "   URL: $mcpServerUri/api/tools" -ForegroundColor Gray
Write-Host "   API Key: ********(hidden - retrieve from Azure Portal or azd env get-values)" -ForegroundColor Gray
Write-Host ""