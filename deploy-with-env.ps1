# Deploy MCP Server with Environment Variables
# This script reads .env.local file and deploys to Azure Container Apps

param(
    [string]$EnvFile = ".env.local",
    [string]$ResourceGroup = "",
    [string]$Location = "",
    [switch]$DryRun = $false
)

# Colors for output
$ErrorColor = "Red"
$SuccessColor = "Green"
$InfoColor = "Cyan"
$WarningColor = "Yellow"

function Write-Info($message) { Write-Host $message -ForegroundColor $InfoColor }
function Write-Success($message) { Write-Host $message -ForegroundColor $SuccessColor }
function Write-Warning($message) { Write-Host $message -ForegroundColor $WarningColor }
function Write-Error($message) { Write-Host $message -ForegroundColor $ErrorColor }

function Read-EnvFile {
    param([string]$FilePath)
    
    $envVars = @{}
    
    if (-not (Test-Path $FilePath)) {
        Write-Error "Environment file '$FilePath' not found!"
        Write-Info "Please copy .env.example to .env.local and fill in your values"
        exit 1
    }
    
    Write-Info "Reading environment variables from: $FilePath"
    
    Get-Content $FilePath | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $parts = $line.Split("=", 2)
            $key = $parts[0].Trim()
            $value = $parts[1].Trim()
            
            # Remove quotes if present
            if ($value.StartsWith('"') -and $value.EndsWith('"')) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            if ($value.StartsWith("'") -and $value.EndsWith("'")) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            
            $envVars[$key] = $value
            Write-Info "  $key = $value"
        }
    }
    
    return $envVars
}

function Validate-EnvVars {
    param([hashtable]$EnvVars)
    
    $required = @("SEARCH_ENDPOINT", "SEARCH_KEY", "SEARCH_INDEX", "SERVER_API_KEY")
    $missing = @()
    
    foreach ($var in $required) {
        if (-not $EnvVars.ContainsKey($var) -or [string]::IsNullOrWhiteSpace($EnvVars[$var])) {
            $missing += $var
        }
    }
    
    if ($missing.Count -gt 0) {
        Write-Error "Missing required environment variables:"
        $missing | ForEach-Object { Write-Error "  - $_" }
        exit 1
    }
    
    Write-Success "All required environment variables are present"
}

function Deploy-ToAzure {
    param(
        [hashtable]$EnvVars,
        [string]$ResourceGroup,
        [string]$Location,
        [bool]$DryRun
    )
    
    # Use values from env file if not provided as parameters
    if ([string]::IsNullOrEmpty($ResourceGroup) -and $EnvVars.ContainsKey("AZURE_RESOURCE_GROUP")) {
        $ResourceGroup = $EnvVars["AZURE_RESOURCE_GROUP"]
    }
    if ([string]::IsNullOrEmpty($Location) -and $EnvVars.ContainsKey("AZURE_LOCATION")) {
        $Location = $EnvVars["AZURE_LOCATION"]
    }
    
    # Default values
    if ([string]::IsNullOrEmpty($ResourceGroup)) { $ResourceGroup = "mcpserver" }
    if ([string]::IsNullOrEmpty($Location)) { $Location = "swedencentral" }
    
    Write-Info "Deployment Configuration:"
    Write-Info "  Resource Group: $ResourceGroup"
    Write-Info "  Location: $Location"
    Write-Info "  Dry Run: $DryRun"
    
    if ($DryRun) {
        Write-Warning "DRY RUN MODE - No actual deployment will occur"
        Write-Info "Environment variables that would be deployed:"
        $EnvVars.GetEnumerator() | Where-Object { $_.Key.StartsWith("SEARCH_") -or $_.Key -eq "SERVER_API_KEY" -or $_.Key -eq "PORT" } | ForEach-Object {
            Write-Info "  $($_.Key) = $($_.Value)"
        }
        return
    }
    
    # Check Azure CLI login
    Write-Info "Checking Azure CLI authentication..."
    $loginCheck = az account show 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Please login to Azure CLI first: az login"
        exit 1
    }
    Write-Success "Azure CLI authenticated"
    
    # Check if resource group exists
    Write-Info "Checking resource group '$ResourceGroup'..."
    $rgCheck = az group show --name $ResourceGroup 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Resource group '$ResourceGroup' does not exist. Creating it..."
        az group create --name $ResourceGroup --location $Location
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to create resource group"
            exit 1
        }
        Write-Success "Resource group created"
    } else {
        Write-Success "Resource group exists"
    }
    
    # Update parameters file with environment variables
    Write-Info "Updating deployment parameters..."
    $parametersFile = "infra/main.parameters.json"
    $parameters = Get-Content $parametersFile | ConvertFrom-Json
    
    # Update search index name if provided
    if ($EnvVars.ContainsKey("SEARCH_INDEX")) {
        $parameters.parameters.searchIndexName.value = $EnvVars["SEARCH_INDEX"]
    }
    
    $parameters | ConvertTo-Json -Depth 10 | Set-Content $parametersFile
    
    # Build and push container
    Write-Info "Building and pushing container..."
    docker build -t mcp-azure-pdf .
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Docker build failed"
        exit 1
    }
    
    # Deploy infrastructure
    Write-Info "Deploying infrastructure..."
    $deploymentResult = az deployment group create `
        --resource-group $ResourceGroup `
        --template-file "infra/main.bicep" `
        --parameters "@infra/main.parameters.json" `
        --parameters environmentName="mcp-pdf" `
        --query "properties.outputs" `
        --output json
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Infrastructure deployment failed"
        exit 1
    }
    
    $outputs = $deploymentResult | ConvertFrom-Json
    $containerAppName = $outputs.containerAppName.value
    $containerRegistryName = $outputs.containerRegistryName.value
    
    # Tag and push image
    Write-Info "Pushing container image..."
    $acrLoginServer = az acr show --name $containerRegistryName --resource-group $ResourceGroup --query "loginServer" -o tsv
    az acr login --name $containerRegistryName
    
    docker tag mcp-azure-pdf "$acrLoginServer/mcp-azure-pdf:latest"
    docker push "$acrLoginServer/mcp-azure-pdf:latest"
    
    # Update container app with environment variables
    Write-Info "Updating container app with environment variables..."
    
    # Prepare environment variables for Azure
    $envVarArgs = @()
    
    # Add environment variables (excluding Azure-specific ones)
    $deployVars = @("SEARCH_ENDPOINT", "SEARCH_KEY", "SEARCH_INDEX", "SERVER_API_KEY", "PORT")
    foreach ($var in $deployVars) {
        if ($EnvVars.ContainsKey($var)) {
            if ($var -eq "SEARCH_KEY" -or $var -eq "SERVER_API_KEY") {
                # These should be secrets
                $envVarArgs += "$var=secretref:$($var.ToLower().Replace('_', '-'))"
            } else {
                $envVarArgs += "$var=$($EnvVars[$var])"
            }
        }
    }
    
    # Update secrets first
    if ($EnvVars.ContainsKey("SEARCH_KEY")) {
        az containerapp secret set --name $containerAppName --resource-group $ResourceGroup --secrets "search-key=$($EnvVars['SEARCH_KEY'])"
    }
    if ($EnvVars.ContainsKey("SERVER_API_KEY")) {
        az containerapp secret set --name $containerAppName --resource-group $ResourceGroup --secrets "server-api-key=$($EnvVars['SERVER_API_KEY'])"
    }
    
    # Update environment variables
    if ($envVarArgs.Count -gt 0) {
        $envVarString = $envVarArgs -join " "
        az containerapp update --name $containerAppName --resource-group $ResourceGroup --set-env-vars $envVarString
    }
    
    # Get the app URL
    $appUrl = az containerapp show --name $containerAppName --resource-group $ResourceGroup --query "properties.configuration.ingress.fqdn" -o tsv
    
    Write-Success "`n🎉 Deployment completed successfully!"
    Write-Info "Container App URL: https://$appUrl"
    Write-Info "Health Check: https://$appUrl/health"
    Write-Info "API Endpoint: https://$appUrl/api/search"
    Write-Info "API Key: $($EnvVars['SERVER_API_KEY'])"
    
    Write-Info "`nTest your deployment:"
    Write-Info "curl https://$appUrl/health"
}

# Main execution
Write-Info "🚀 MCP Azure PDF Server Deployment Script"
Write-Info "========================================="

# Read environment variables
$envVars = Read-EnvFile -FilePath $EnvFile

# Validate required variables
Validate-EnvVars -EnvVars $envVars

# Deploy to Azure
Deploy-ToAzure -EnvVars $envVars -ResourceGroup $ResourceGroup -Location $Location -DryRun $DryRun

Write-Success "`n✅ Deployment script completed!"