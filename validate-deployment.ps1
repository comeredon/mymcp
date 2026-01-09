# Deployment Validation Script
# Run this after deployment to verify everything is configured correctly

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName
)

Write-Host "🔍 Validating MCP Deployment" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

$errors = @()
$warnings = @()

# Check resource group exists
Write-Host "Checking resource group..." -ForegroundColor Yellow
$rg = az group show --name $ResourceGroupName 2>$null | ConvertFrom-Json
if (-not $rg) {
    $errors += "Resource group '$ResourceGroupName' not found"
    Write-Host "❌ Resource group not found" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Resource group exists: $($rg.name)" -ForegroundColor Green

# Get all resources
Write-Host "`nChecking deployed resources..." -ForegroundColor Yellow
$resources = az resource list --resource-group $ResourceGroupName --query "[].{name:name, type:type}" | ConvertFrom-Json

# Required resources
$requiredResources = @{
    "Microsoft.OperationalInsights/workspaces" = "Log Analytics Workspace"
    "Microsoft.ManagedIdentity/userAssignedIdentities" = "Managed Identity"
    "Microsoft.ContainerRegistry/registries" = "Container Registry"
    "Microsoft.App/managedEnvironments" = "Container Apps Environment"
    "Microsoft.App/containerApps" = "Container App"
    "Microsoft.Search/searchServices" = "AI Search Service"
    "Microsoft.Storage/storageAccounts" = "Storage Account"
    "Microsoft.CognitiveServices/accounts" = "Azure OpenAI"
}

foreach ($type in $requiredResources.Keys) {
    $resource = $resources | Where-Object { $_.type -eq $type }
    if ($resource) {
        Write-Host "✅ $($requiredResources[$type]): $($resource.name)" -ForegroundColor Green
    } else {
        $errors += "Missing required resource: $($requiredResources[$type])"
        Write-Host "❌ $($requiredResources[$type]) not found" -ForegroundColor Red
    }
}

# Check container app status
Write-Host "`nChecking container app status..." -ForegroundColor Yellow
$containerApp = $resources | Where-Object { $_.type -eq "Microsoft.App/containerApps" }
if ($containerApp) {
    $appStatus = az containerapp show --name $containerApp.name --resource-group $ResourceGroupName --query "properties.runningStatus" -o tsv
    if ($appStatus -eq "Running") {
        Write-Host "✅ Container app is running" -ForegroundColor Green
    } else {
        $warnings += "Container app status: $appStatus"
        Write-Host "⚠️  Container app status: $appStatus" -ForegroundColor Yellow
    }
}

# Check storage containers
Write-Host "`nChecking storage containers..." -ForegroundColor Yellow
$storageAccount = $resources | Where-Object { $_.type -eq "Microsoft.Storage/storageAccounts" }
if ($storageAccount) {
    $containers = az storage container list --account-name $storageAccount.name --auth-mode login --query "[].name" -o json 2>$null | ConvertFrom-Json
    if ($containers -contains "pdfs") {
        Write-Host "✅ 'pdfs' container exists" -ForegroundColor Green
    } else {
        $warnings += "Storage container 'pdfs' not found"
        Write-Host "⚠️  'pdfs' container not found" -ForegroundColor Yellow
    }
    if ($containers -contains "documents") {
        Write-Host "✅ 'documents' container exists" -ForegroundColor Green
    } else {
        $warnings += "Storage container 'documents' not found"
        Write-Host "⚠️  'documents' container not found" -ForegroundColor Yellow
    }
}

# Check Azure OpenAI deployments
Write-Host "`nChecking Azure OpenAI deployments..." -ForegroundColor Yellow
$openAI = $resources | Where-Object { $_.type -eq "Microsoft.CognitiveServices/accounts" }
if ($openAI) {
    $deployments = az cognitiveservices account deployment list --name $openAI.name --resource-group $ResourceGroupName --query "[].name" -o json 2>$null | ConvertFrom-Json
    if ($deployments -contains "embeddings") {
        Write-Host "✅ 'embeddings' deployment exists" -ForegroundColor Green
    } else {
        $warnings += "OpenAI 'embeddings' deployment not found"
        Write-Host "⚠️  'embeddings' deployment not found" -ForegroundColor Yellow
    }
    if ($deployments -contains "chat") {
        Write-Host "✅ 'chat' deployment exists" -ForegroundColor Green
    } else {
        $warnings += "OpenAI 'chat' deployment not found"
        Write-Host "⚠️  'chat' deployment not found" -ForegroundColor Yellow
    }
}

# Check role assignments
Write-Host "`nChecking role assignments..." -ForegroundColor Yellow
$managedIdentity = $resources | Where-Object { $_.type -eq "Microsoft.ManagedIdentity/userAssignedIdentities" }
if ($managedIdentity) {
    # Get the principal ID of the managed identity
    $identityDetails = az identity show --name $managedIdentity.name --resource-group $ResourceGroupName 2>$null | ConvertFrom-Json
    if ($identityDetails -and $identityDetails.principalId) {
        $roleAssignments = az role assignment list --assignee $identityDetails.principalId --resource-group $ResourceGroupName --query "[].roleDefinitionName" -o json 2>$null | ConvertFrom-Json
        
        $requiredRoles = @("AcrPull", "Search Index Data Contributor", "Storage Blob Data Contributor", "Cognitive Services OpenAI User")
        foreach ($role in $requiredRoles) {
            if ($roleAssignments -contains $role) {
                Write-Host "✅ Role assigned: $role" -ForegroundColor Green
            } else {
                $warnings += "Role assignment not found: $role"
                Write-Host "⚠️  Role not assigned: $role" -ForegroundColor Yellow
            }
        }
    } else {
        $warnings += "Could not retrieve managed identity principal ID"
        Write-Host "⚠️  Could not retrieve managed identity details" -ForegroundColor Yellow
    }
}

# Test health endpoint
Write-Host "`nTesting health endpoint..." -ForegroundColor Yellow
if ($containerApp) {
    $appUrl = az containerapp show --name $containerApp.name --resource-group $ResourceGroupName --query "properties.configuration.ingress.fqdn" -o tsv
    if ($appUrl) {
        $healthUrl = "https://$appUrl/health"
        try {
            $response = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 10
            if ($response.StatusCode -eq 200) {
                Write-Host "✅ Health endpoint responding: $healthUrl" -ForegroundColor Green
            } else {
                $warnings += "Health endpoint returned status: $($response.StatusCode)"
                Write-Host "⚠️  Health endpoint status: $($response.StatusCode)" -ForegroundColor Yellow
            }
        } catch {
            $errors += "Health endpoint not accessible: $healthUrl"
            Write-Host "❌ Health endpoint not accessible: $healthUrl" -ForegroundColor Red
        }
    }
}

# Summary
Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host "📊 Validation Summary" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan

if ($errors.Count -eq 0 -and $warnings.Count -eq 0) {
    Write-Host "✅ All checks passed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Your deployment is ready to use!" -ForegroundColor Green
    exit 0
} else {
    if ($errors.Count -gt 0) {
        Write-Host ""
        Write-Host "❌ Errors ($($errors.Count)):" -ForegroundColor Red
        foreach ($error in $errors) {
            Write-Host "   - $error" -ForegroundColor Red
        }
    }
    
    if ($warnings.Count -gt 0) {
        Write-Host ""
        Write-Host "⚠️  Warnings ($($warnings.Count)):" -ForegroundColor Yellow
        foreach ($warning in $warnings) {
            Write-Host "   - $warning" -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
    if ($errors.Count -gt 0) {
        Write-Host "Please address the errors before using the deployment." -ForegroundColor Red
        exit 1
    } else {
        Write-Host "Deployment has warnings but should be functional." -ForegroundColor Yellow
        exit 0
    }
}
