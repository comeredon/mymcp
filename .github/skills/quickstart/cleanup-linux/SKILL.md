---
name: cleanup-linux
description: Step-by-step cleanup guide for the MCP Azure PDF Server on Linux / WSL2 using cleanup.sh. Covers resource group deletion, search pipeline cleanup, and purging soft-deleted resources.
---

# Cleanup — MCP Azure PDF Server on Linux / WSL2

## Overview

This skill breaks the `cleanup.sh` script into discrete steps for tearing down Azure resources. Use it to clean up a deployment, free soft-deleted resource names, or selectively remove components.

## Prerequisites

- Azure CLI authenticated (`az login`)
- `jq` installed
- `curl` installed (for search pipeline cleanup)

---

## Step 1: Verify Azure Authentication

```bash
az account show --query "{user:user.name, subscription:name}" -o table
```

## Step 2: Review Resources Before Deletion

```bash
RESOURCE_GROUP_NAME="mcp-server-rg"

az resource list --resource-group "$RESOURCE_GROUP_NAME" \
    --query "[].{Name:name, Type:type}" -o table
```

## Step 3: Clean Up Search Pipeline (Optional)

Delete the search pipeline components before deleting the resource group. This ensures clean state if you plan to redeploy.

```bash
# Find search service
search_service=$(az resource list --resource-group "$RESOURCE_GROUP_NAME" \
    --resource-type "Microsoft.Search/searchServices" \
    --query "[0].name" -o tsv 2>/dev/null)

if [[ -n "$search_service" ]]; then
    TOKEN=$(az account get-access-token --resource https://search.azure.com/ --query accessToken -o tsv)
    BASE="https://$search_service.search.windows.net"
    API="api-version=2025-11-01-Preview"

    # Delete in order: indexer → skillset → index → datasource
    for component in "indexers/pdf-indexer" "skillsets/pdf-skillset" "indexes/pdf-index" "datasources/pdf-datasource"; do
        echo "Deleting $component..."
        curl -s -X DELETE "$BASE/$component?$API" -H "Authorization: Bearer $TOKEN" \
            && echo "  ✅ Deleted" || echo "  ⚠️ Not found"
    done
fi
```

## Step 4: Delete Resource Group

```bash
az group delete --name "$RESOURCE_GROUP_NAME" --yes --no-wait
echo "✅ Resource group deletion initiated (runs in background)"
```

To wait for completion:

```bash
az group wait --name "$RESOURCE_GROUP_NAME" --deleted --timeout 600 2>/dev/null || true
```

## Step 5: Purge Soft-Deleted Cognitive Services (Azure AI Foundry)

Soft-deleted Cognitive Services resources block name reuse. Purge them:

```bash
echo "Checking for soft-deleted Cognitive Services..."
deleted=$(az cognitiveservices account list-deleted \
    --query "[].{name:name, location:location}" -o json 2>/dev/null || echo "[]")

echo "$deleted" | jq -c '.[]' | while read -r item; do
    name=$(echo "$item" | jq -r '.name')
    location=$(echo "$item" | jq -r '.location')
    echo "Purging $name ($location)..."
    # Do NOT use --resource-group for soft-deleted resources
    az cognitiveservices account purge --name "$name" --location "$location" 2>/dev/null \
        || az rest --method DELETE \
            --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/providers/Microsoft.CognitiveServices/locations/$location/deletedAccounts/$name?api-version=2023-05-01" \
            2>/dev/null \
        || echo "⚠️ Failed: $name"
done
```

**Important**: The `--resource-group` parameter is **invalid** for purging soft-deleted Cognitive Services. Omit it.

## Step 6: Purge Soft-Deleted API Management

```bash
echo "Checking for soft-deleted APIM instances..."
subscription_id=$(az account show --query "id" -o tsv)

deleted_apim=$(az rest --method GET \
    --url "https://management.azure.com/subscriptions/$subscription_id/providers/Microsoft.ApiManagement/deletedservices?api-version=2022-08-01" \
    2>/dev/null || echo '{"value":[]}')

echo "$deleted_apim" | jq -c '.value[]' | while read -r item; do
    name=$(echo "$item" | jq -r '.name')
    location=$(echo "$item" | jq -r '.location')
    echo "Purging APIM $name ($location)..."
    az rest --method DELETE \
        --url "https://management.azure.com/subscriptions/$subscription_id/providers/Microsoft.ApiManagement/locations/$location/deletedservices/$name?api-version=2022-08-01" \
        2>/dev/null || echo "⚠️ Failed: $name"
done
```

## Step 7: Purge Soft-Deleted Key Vaults

```bash
echo "Checking for soft-deleted Key Vaults..."
deleted_kv=$(az keyvault list-deleted \
    --query "[].{name:name, location:location}" -o json 2>/dev/null || echo "[]")

echo "$deleted_kv" | jq -c '.[]' | while read -r item; do
    name=$(echo "$item" | jq -r '.name')
    location=$(echo "$item" | jq -r '.location')
    echo "Purging Key Vault $name ($location)..."
    az keyvault purge --name "$name" --location "$location" 2>/dev/null \
        || echo "⚠️ Failed: $name"
done
```

## Step 8: Purge Soft-Deleted Storage Accounts

```bash
echo "Checking for soft-deleted Storage Accounts..."
subscription_id=$(az account show --query "id" -o tsv)
deleted_storage=$(az storage account list --include-deleted \
    --query "[?deletedTime != null].{name:name, location:location}" -o json 2>/dev/null || echo "[]")

echo "$deleted_storage" | jq -c '.[]' | while read -r item; do
    name=$(echo "$item" | jq -r '.name')
    location=$(echo "$item" | jq -r '.location')
    echo "Purging Storage Account $name ($location)..."
    az rest --method DELETE \
        --url "https://management.azure.com/subscriptions/$subscription_id/providers/Microsoft.Storage/locations/$location/deletedAccounts/$name?api-version=2022-09-01" \
        2>/dev/null || echo "⚠️ Failed: $name"
done
```

## Step 9: Verify Cleanup

```bash
# Resource group gone?
az group show --name "$RESOURCE_GROUP_NAME" 2>/dev/null \
    && echo "⚠️ Still exists" || echo "✅ Resource group deleted"

# Soft-deleted resources gone?
echo "=== Cognitive Services ===" && az cognitiveservices account list-deleted -o table 2>/dev/null
echo "=== Key Vaults ===" && az keyvault list-deleted -o table 2>/dev/null
echo "=== Storage ===" && az storage account list --include-deleted --query "[?deletedTime != null]" -o table 2>/dev/null
echo "=== APIM ===" && az rest --method GET \
    --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/providers/Microsoft.ApiManagement/deletedservices?api-version=2022-08-01" \
    --query "value[].{name:name}" -o table 2>/dev/null
```

---

## One-Command Cleanup

```bash
# Delete resource group + purge all soft-deleted resources
bash cleanup.sh --purge-all --yes

# Delete resource group only (no purge)
bash cleanup.sh --yes

# Custom resource group
bash cleanup.sh --resource-group my-custom-rg --purge-all --yes
```

### Script Flags

| Flag | Description |
|------|-------------|
| `--resource-group NAME` | Resource group to delete (default: `mcp-server-rg`) |
| `--purge-cognitive` | Purge soft-deleted Azure AI Foundry |
| `--purge-apim` | Purge soft-deleted API Management |
| `--purge-keyvault` | Purge soft-deleted Key Vaults |
| `--purge-storage` | Purge soft-deleted Storage Accounts |
| `--cleanup-search` | Clean up search pipeline (indexer, skillset, index, datasource) |
| `--purge-all` | All purge flags + cleanup-search |
| `--yes` | Skip confirmation prompt |

## Common Issues

| Problem | Solution |
|---------|----------|
| Resource group stuck in "Deleting" | APIM can take 10-15 min. Wait: `az group wait --name <rg> --deleted --timeout 900` |
| "Name already in use" on redeploy | Use `--purge-all` to free names |
| Cognitive Services purge "ResourceGroupParameterInvalid" | Remove `--resource-group` — soft-deleted resources aren't tied to RGs |
| Permission denied during purge | Need `Contributor` or `Owner` role on the subscription |
| APIM purge fails immediately after deletion | Wait 5-10 minutes for soft-delete registration |

## Redeploy After Cleanup

```bash
bash deploy.sh --deploy-apim --deploy-vnet
```
