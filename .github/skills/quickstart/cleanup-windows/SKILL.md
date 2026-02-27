---
name: cleanup-windows
description: Step-by-step cleanup guide for the MCP Azure PDF Server on Windows using cleanup.ps1 (PowerShell). Covers resource group deletion, search pipeline cleanup, and purging soft-deleted resources.
---

# Cleanup — MCP Azure PDF Server on Windows (PowerShell)

## Overview

This skill breaks the `cleanup.ps1` script into discrete steps for tearing down Azure resources on Windows. Use it to clean up a deployment, free soft-deleted resource names, or selectively remove components.

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- PowerShell 7+ recommended (works with Windows PowerShell 5.1)

---

## Step 1: Verify Azure Authentication

```powershell
az account show --query "{user:user.name, subscription:name}" -o table
```

## Step 2: Review Resources Before Deletion

```powershell
$ResourceGroupName = "mcp-server-rg"

az resource list --resource-group $ResourceGroupName `
    --query "[].{Name:name, Type:type}" -o table
```

## Step 3: Clean Up Search Pipeline (Optional)

Delete the search pipeline components before deleting the resource group:

```powershell
$searchService = az resource list --resource-group $ResourceGroupName `
    --resource-type "Microsoft.Search/searchServices" `
    --query "[0].name" -o tsv 2>$null

if ($searchService) {
    $token = az account get-access-token --resource https://search.azure.com/ --query accessToken -o tsv
    $headers = @{ "Authorization" = "Bearer $token" }
    $base = "https://$searchService.search.windows.net"
    $api = "api-version=2025-05-01-Preview"

    # Delete in order: indexer → skillset → index → datasource
    foreach ($component in @("indexers/pdf-indexer", "skillsets/pdf-skillset", "indexes/pdf-index", "datasources/pdf-datasource")) {
        Write-Host "  Deleting $component..."
        try {
            Invoke-RestMethod -Uri "$base/$($component)?$api" -Method DELETE -Headers $headers -ErrorAction Stop
            Write-Host "    ✅ Deleted" -ForegroundColor Green
        } catch {
            Write-Host "    ⚠️ Not found" -ForegroundColor Yellow
        }
    }
}
```

## Step 4: Delete Resource Group

```powershell
az group delete --name $ResourceGroupName --yes --no-wait
Write-Host "✅ Resource group deletion initiated" -ForegroundColor Green
```

To wait for completion:

```powershell
az group wait --name $ResourceGroupName --deleted --timeout 600 2>$null
Start-Sleep -Seconds 10
```

## Step 5: Purge Soft-Deleted Cognitive Services (Azure OpenAI)

```powershell
Write-Host "Checking for soft-deleted Cognitive Services..."
$deleted = az cognitiveservices account list-deleted `
    --query "[].{name:name, location:location}" -o json 2>$null | ConvertFrom-Json

foreach ($item in $deleted) {
    Write-Host "  Purging $($item.name) ($($item.location))..."
    # Do NOT use --resource-group for soft-deleted resources
    az cognitiveservices account purge --name $item.name --location $item.location 2>$null
    if ($LASTEXITCODE -ne 0) {
        $subscriptionId = az account show --query id -o tsv
        az rest --method DELETE `
            --url "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.CognitiveServices/locations/$($item.location)/deletedAccounts/$($item.name)?api-version=2023-05-01" `
            2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    ⚠️ Failed: $($item.name)" -ForegroundColor Yellow
        }
    }
    Write-Host "    ✅ Purged" -ForegroundColor Green
}
```

**Important**: The `--resource-group` parameter is **invalid** for purging soft-deleted Cognitive Services. Omit it.

## Step 6: Purge Soft-Deleted API Management

```powershell
Write-Host "Checking for soft-deleted APIM instances..."
$subscriptionId = az account show --query id -o tsv

$response = az rest --method GET `
    --url "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.ApiManagement/deletedservices?api-version=2022-08-01" `
    2>$null | ConvertFrom-Json

foreach ($item in $response.value) {
    Write-Host "  Purging APIM $($item.name) ($($item.location))..."
    az rest --method DELETE `
        --url "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.ApiManagement/locations/$($item.location)/deletedservices/$($item.name)?api-version=2022-08-01" `
        2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    ✅ Purged" -ForegroundColor Green
    } else {
        Write-Host "    ⚠️ Failed" -ForegroundColor Yellow
    }
}
```

## Step 7: Purge Soft-Deleted Key Vaults

```powershell
Write-Host "Checking for soft-deleted Key Vaults..."
$deletedKv = az keyvault list-deleted `
    --query "[].{name:name, location:location}" -o json 2>$null | ConvertFrom-Json

foreach ($item in $deletedKv) {
    Write-Host "  Purging Key Vault $($item.name) ($($item.location))..."
    az keyvault purge --name $item.name --location $item.location 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    ✅ Purged" -ForegroundColor Green
    } else {
        Write-Host "    ⚠️ Failed" -ForegroundColor Yellow
    }
}
```

## Step 8: Purge Soft-Deleted Storage Accounts

```powershell
Write-Host "Checking for soft-deleted Storage Accounts..."
$subscriptionId = az account show --query id -o tsv
$deletedStorage = az storage account list --include-deleted `
    --query "[?deletedTime != null].{name:name, location:location}" -o json 2>$null | ConvertFrom-Json

foreach ($item in $deletedStorage) {
    Write-Host "  Purging Storage Account $($item.name) ($($item.location))..."
    az rest --method DELETE `
        --url "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Storage/locations/$($item.location)/deletedAccounts/$($item.name)?api-version=2022-09-01" `
        2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    ✅ Purged" -ForegroundColor Green
    } else {
        Write-Host "    ⚠️ Failed" -ForegroundColor Yellow
    }
}
```

## Step 9: Verify Cleanup

```powershell
# Resource group gone?
try {
    az group show --name $ResourceGroupName --output none 2>$null
    Write-Host "⚠️ Resource group still exists" -ForegroundColor Yellow
} catch {
    Write-Host "✅ Resource group deleted" -ForegroundColor Green
}

# Soft-deleted resources
Write-Host "`n=== Cognitive Services ===" -ForegroundColor Cyan
az cognitiveservices account list-deleted -o table 2>$null
Write-Host "`n=== Key Vaults ===" -ForegroundColor Cyan
az keyvault list-deleted -o table 2>$null
Write-Host "`n=== Storage ===" -ForegroundColor Cyan
az storage account list --include-deleted --query "[?deletedTime != null]" -o table 2>$null
```

---

## One-Command Cleanup

```powershell
# Delete resource group + purge all soft-deleted resources
.\cleanup.ps1 -PurgeAll -Yes

# Delete resource group only (no purge)
.\cleanup.ps1 -Yes

# Custom resource group
.\cleanup.ps1 -ResourceGroupName "my-custom-rg" -PurgeAll -Yes
```

### Script Parameters

| Parameter | Description |
|-----------|-------------|
| `-ResourceGroupName` | Resource group to delete (default: `mcp-server-rg`) |
| `-PurgeCognitive` | Purge soft-deleted Azure OpenAI |
| `-PurgeApim` | Purge soft-deleted API Management |
| `-PurgeKeyvault` | Purge soft-deleted Key Vaults |
| `-PurgeStorage` | Purge soft-deleted Storage Accounts |
| `-CleanupSearch` | Clean up search pipeline (indexer, skillset, index, datasource) |
| `-PurgeAll` | All purge flags + cleanup-search |
| `-Yes` | Skip confirmation prompt |

## Common Issues

| Problem | Solution |
|---------|----------|
| Resource group stuck in "Deleting" | APIM can take 10-15 min. Wait: `az group wait --name <rg> --deleted --timeout 900` |
| "Name already in use" on redeploy | Use `-PurgeAll` to free names |
| Cognitive Services purge "ResourceGroupParameterInvalid" | Omit `-ResourceGroup` — soft-deleted resources aren't tied to RGs |
| Permission denied during purge | Need `Contributor` or `Owner` role on the subscription |
| Execution policy error | Run `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser` |

## Redeploy After Cleanup

```powershell
.\deploy.ps1 -DeployApim $true -DeployVNet $true
```
