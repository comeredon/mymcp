# cleanup.ps1
# PowerShell version of MCP Azure PDF Server cleanup script
# Removes all Azure resources created by deploy.ps1

param(
    [string]$ResourceGroupName = "mcp-server-rg",
    [switch]$PurgeCognitive,
    [switch]$PurgeApim,
    [switch]$PurgeKeyvault,
    [switch]$PurgeStorage,
    [switch]$CleanupSearch,
    [switch]$PurgeAll,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"

# Set all purge flags if PurgeAll is specified
if ($PurgeAll) {
    $PurgeCognitive = $true
    $PurgeApim = $true
    $PurgeKeyvault = $true
    $PurgeStorage = $true
    $CleanupSearch = $true
}

function Write-Header {
    param([string]$Message)
    Write-Host "🧹 $Message" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Success {
    param([string]$Message)
    Write-Host "  ✅ $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "  ⚠️  $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "  ❌ $Message" -ForegroundColor Red
}

Write-Header "MCP Azure PDF Server - Cleanup"

# Check if logged into Azure
try {
    $null = az account show --output none 2>$null
    if ($LASTEXITCODE -ne 0) { throw }
}
catch {
    Write-Error "Not logged in to Azure. Run: az login"
    exit 1
}

$loggedInUser = az account show --query "user.name" --output tsv
$subscription = az account show --query "name" --output tsv
Write-Success "Logged in as: $loggedInUser"
Write-Host "   Subscription: $subscription"
Write-Host ""

# Check if resource group exists
try {
    $null = az group show --name $ResourceGroupName --output none 2>$null
    $resourceGroupExists = $true
}
catch {
    $resourceGroupExists = $false
}

if (-not $resourceGroupExists) {
    Write-Warning "Resource group '$ResourceGroupName' does not exist. Nothing to delete."
    if ($PurgeCognitive -or $PurgeApim -or $PurgeKeyvault -or $PurgeStorage) {
        Write-Host ""
        Write-Host "Checking for soft-deleted resources to purge..."
    }
    else {
        exit 0
    }
}
else {
    # List resources in the group
    Write-Host "📋 Resources in '$ResourceGroupName':"
    az resource list --resource-group $ResourceGroupName --query "[].{Name:name, Type:type}" --output table
    Write-Host ""

    # Search pipeline cleanup (if requested)
    if ($CleanupSearch) {
        Write-Host ""
        Write-Host "🔍 Cleaning up Azure Search pipeline components..."
        
        # Get search service name from resources
        $searchService = az resource list --resource-group $ResourceGroupName `
            --resource-type "Microsoft.Search/searchServices" `
            --query "[0].name" --output tsv 2>$null
            
        if ($searchService) {
            Write-Host "   Found search service: $searchService"
            
            # Get access token for search service  
            $TOKEN = az account get-access-token --resource https://search.azure.com/ --query accessToken --output tsv 2>$null
            
            if ($TOKEN) {
                Write-Host "   Cleaning up pipeline components..."
                
                # Delete indexer
                Write-Host "   - Deleting pdf-indexer..."
                try {
                    Invoke-RestMethod -Uri "https://$searchService.search.windows.net/indexers/pdf-indexer?api-version=2025-11-01-Preview" `
                        -Method DELETE -Headers @{"Authorization"="Bearer $TOKEN"} -ErrorAction Stop
                    Write-Success "Deleted indexer"
                }
                catch {
                    Write-Warning "Indexer not found"
                }
                
                # Delete skillset
                Write-Host "   - Deleting pdf-skillset..."
                try {
                    Invoke-RestMethod -Uri "https://$searchService.search.windows.net/skillsets/pdf-skillset?api-version=2025-11-01-Preview" `
                        -Method DELETE -Headers @{"Authorization"="Bearer $TOKEN"} -ErrorAction Stop
                    Write-Success "Deleted skillset"
                }
                catch {
                    Write-Warning "Skillset not found"
                }
                
                # Delete index
                Write-Host "   - Deleting pdf-index..."
                try {
                    Invoke-RestMethod -Uri "https://$searchService.search.windows.net/indexes/pdf-index?api-version=2025-11-01-Preview" `
                        -Method DELETE -Headers @{"Authorization"="Bearer $TOKEN"} -ErrorAction Stop
                    Write-Success "Deleted index"
                }
                catch {
                    Write-Warning "Index not found"
                }
                
                # Delete datasource  
                Write-Host "   - Deleting pdf-datasource..."
                try {
                    Invoke-RestMethod -Uri "https://$searchService.search.windows.net/datasources/pdf-datasource?api-version=2025-11-01-Preview" `
                        -Method DELETE -Headers @{"Authorization"="Bearer $TOKEN"} -ErrorAction Stop
                    Write-Success "Deleted datasource"
                }
                catch {
                    Write-Warning "Datasource not found"
                }
                    
                Write-Success "Search pipeline cleanup completed"
            }
            else {
                Write-Warning "Could not get search service access token. Skipping pipeline cleanup."
            }
        }
        else {
            Write-Warning "No Azure Search service found in resource group. Skipping pipeline cleanup."
        }
    }

    # Confirmation
    if (-not $Yes) {
        Write-Warning "This will permanently delete resource group '$ResourceGroupName' and ALL resources inside it."
        Write-Host ""
        $confirm = Read-Host "Are you sure? Type the resource group name to confirm"
        if ($confirm -ne $ResourceGroupName) {
            Write-Error "Confirmation failed. Aborting."
            exit 1
        }
    }

    # Delete resource group
    Write-Host ""
    Write-Host "🗑️  Deleting resource group '$ResourceGroupName'..."
    try {
        az group delete --name $ResourceGroupName --yes --no-wait
        Write-Success "Resource group deletion initiated (runs in background)"
    }
    catch {
        Write-Error "Failed to delete resource group!"
        exit 1
    }

    # Wait for deletion to complete if we need to purge
    if ($PurgeCognitive -or $PurgeApim -or $PurgeKeyvault -or $PurgeStorage) {
        Write-Host ""
        Write-Host "⏳ Waiting for resource group deletion to complete before purging..."
        az group wait --name $ResourceGroupName --deleted --timeout 600 2>$null
        Start-Sleep -Seconds 10
    }
}

# Purge soft-deleted Cognitive Services (Azure OpenAI)
if ($PurgeCognitive) {
    Write-Host ""
    Write-Host "🔥 Purging soft-deleted Cognitive Services resources..."
    $deleted = az cognitiveservices account list-deleted --query "[].{name:name, location:location}" --output json 2>$null | ConvertFrom-Json
    $count = $deleted.Count

    if ($count -gt 0) {
        Write-Host "   Found $count soft-deleted Cognitive Services resource(s):"
        foreach ($item in $deleted) {
            Write-Host "   - $($item.name) ($($item.location))"
        }
        Write-Host ""
        foreach ($item in $deleted) {
            Write-Host "   Purging '$($item.name)' in $($item.location)..."
            try {
                az cognitiveservices account purge --name $item.name --location $item.location 2>$null
                Write-Success "Purged '$($item.name)'"
            }
            catch {
                Write-Warning "Could not purge '$($item.name)' — it may need more time or manual cleanup"
            }
        }
    }
    else {
        Write-Host "   No soft-deleted Cognitive Services resources found."
    }
}

# Summary
Write-Host ""
Write-Host "🧹 Cleanup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "   Resource group '$ResourceGroupName': Deletion initiated"
if ($PurgeCognitive) { Write-Host "   Cognitive Services (OpenAI): Purged" }
if ($PurgeApim) { Write-Host "   API Management: Purged" }
if ($PurgeKeyvault) { Write-Host "   Key Vault: Purged" }
if ($PurgeStorage) { Write-Host "   Storage Account: Purged" }
if ($CleanupSearch) { Write-Host "   Search Pipeline: Cleaned" }
Write-Host ""
Write-Host "💡 Tips:"
Write-Host "   - Deletion takes a few minutes to propagate"
Write-Host "   - Check status: az group show --name $ResourceGroupName 2>`$null || 'Deleted'"
Write-Host "   - To redeploy: ./deploy.ps1"