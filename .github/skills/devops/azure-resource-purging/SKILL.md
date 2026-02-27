---
name: azure-resource-purging
description: Purge soft-deleted Azure resources to free up names and avoid deployment conflicts. Use when encountering "resource name already in use" errors or before redeployment with same names.
---

# Azure Soft-Deleted Resource Purging

## Overview

Many Azure services use soft-delete by default, which prevents immediate name reuse after deletion. This skill provides commands to purge soft-deleted resources across different Azure services.

## Prerequisites

- Azure CLI authenticated with appropriate permissions
- `jq` for JSON processing (install: `sudo apt install jq`)
- Sufficient Azure RBAC permissions:
  - **Cognitive Services**: `Contributor` or `Cognitive Services Contributor`
  - **Key Vault**: `Key Vault Contributor` or custom role with `Microsoft.KeyVault/locations/deletedVaults/purge/action`
  - **API Management**: `API Management Service Contributor` or `Contributor`
  - **Storage Account**: `Storage Account Contributor` or `Contributor`

## 1. Cognitive Services (Azure OpenAI)

### List soft-deleted instances

```bash
az cognitiveservices account list-deleted -o table
```

### Purge specific instance

```bash
# Note: Soft-deleted resources are not tied to resource groups
az cognitiveservices account purge \
    --name <account-name> \
    --location <region>
```

### Purge all soft-deleted instances

```bash
az cognitiveservices account list-deleted --query "[].{name:name, location:location}" -o json | \
jq -c '.[]' | while read -r item; do
    name=$(echo "$item" | jq -r '.name')
    location=$(echo "$item" | jq -r '.location')
    echo "Purging Cognitive Services: $name ($location)"
    # Don't use --resource-group for soft-deleted resources
    az cognitiveservices account purge --name "$name" --location "$location" || echo "Failed: $name"
done
```

**Alternative REST API method:**

```bash
# If CLI command fails, use REST API
subscription_id=$(az account show --query "id" -o tsv)
az cognitiveservices account list-deleted --query "[].{name:name, location:location}" -o json | \
jq -c '.[]' | while read -r item; do
    name=$(echo "$item" | jq -r '.name')
    location=$(echo "$item" | jq -r '.location')
    echo "Purging via REST: $name ($location)"
    az rest --method DELETE \
        --url "https://management.azure.com/subscriptions/$subscription_id/providers/Microsoft.CognitiveServices/locations/$location/deletedAccounts/$name?api-version=2023-05-01" \
        || echo "Failed: $name"
done
```

## 2. Key Vault

### List soft-deleted Key Vaults

```bash
az keyvault list-deleted -o table
```

### Purge specific Key Vault

```bash
az keyvault purge --name <vault-name> --location <region>
```

### Purge all soft-deleted Key Vaults

```bash
az keyvault list-deleted --query "[].{name:name, location:location}" -o json | \
jq -c '.[]' | while read -r item; do
    name=$(echo "$item" | jq -r '.name')
    location=$(echo "$item" | jq -r '.location')
    echo "Purging Key Vault: $name ($location)"
    az keyvault purge --name "$name" --location "$location" || echo "Failed: $name"
done
```

## 3. API Management

### List soft-deleted APIM instances

```bash
subscription_id=$(az account show --query "id" -o tsv)
az rest --method GET \
    --url "https://management.azure.com/subscriptions/$subscription_id/providers/Microsoft.ApiManagement/deletedservices?api-version=2022-08-01" \
    | jq '.value[] | {name, location}'
```

### Purge specific APIM instance

```bash
subscription_id=$(az account show --query "id" -o tsv)
az rest --method DELETE \
    --url "https://management.azure.com/subscriptions/$subscription_id/providers/Microsoft.ApiManagement/locations/<region>/deletedservices/<apim-name>?api-version=2022-08-01"
```

### Purge all soft-deleted APIM instances

```bash
subscription_id=$(az account show --query "id" -o tsv)
az rest --method GET \
    --url "https://management.azure.com/subscriptions/$subscription_id/providers/Microsoft.ApiManagement/deletedservices?api-version=2022-08-01" | \
jq -c '.value[]' | while read -r item; do
    name=$(echo "$item" | jq -r '.name')
    location=$(echo "$item" | jq -r '.location')
    echo "Purging APIM: $name ($location)"
    az rest --method DELETE \
        --url "https://management.azure.com/subscriptions/$subscription_id/providers/Microsoft.ApiManagement/locations/$location/deletedservices/$name?api-version=2022-08-01" \
        || echo "Failed: $name"
done
```

## 4. Storage Account

### List soft-deleted Storage Accounts

```bash
az storage account list --include-deleted \
    --query "[?deletedTime != null].{name:name, location:location, deletedTime:deletedTime}" -o table
```

### Purge specific Storage Account

```bash
subscription_id=$(az account show --query "id" -o tsv)
az rest --method DELETE \
    --url "https://management.azure.com/subscriptions/$subscription_id/providers/Microsoft.Storage/locations/<region>/deletedAccounts/<storage-name>?api-version=2022-09-01"
```

### Purge all soft-deleted Storage Accounts

```bash
subscription_id=$(az account show --query "id" -o tsv)
az storage account list --include-deleted \
    --query "[?deletedTime != null].{name:name, location:location}" -o json | \
jq -c '.[]' | while read -r item; do
    name=$(echo "$item" | jq -r '.name')
    location=$(echo "$item" | jq -r '.location')
    echo "Purging Storage Account: $name ($location)"
    az rest --method DELETE \
        --url "https://management.azure.com/subscriptions/$subscription_id/providers/Microsoft.Storage/locations/$location/deletedAccounts/$name?api-version=2022-09-01" \
        || echo "Failed: $name"
done
```

## 5. Bulk Purge Script

Create a comprehensive purge script for all resource types:

```bash
#!/bin/bash
# purge-all-soft-deleted.sh

set -euo pipefail

echo "🔥 Purging all soft-deleted Azure resources..."
subscription_id=$(az account show --query "id" -o tsv)

# Cognitive Services
echo "Purging Cognitive Services..."
az cognitiveservices account list-deleted --query "[].{name:name, location:location}" -o json 2>/dev/null | \
jq -c '.[]?' | while read -r item; do
    name=$(echo "$item" | jq -r '.name')
    location=$(echo "$item" | jq -r '.location')
    echo "  Purging: $name ($location)"
    # Don't use --resource-group for soft-deleted resources
    az cognitiveservices account purge --name "$name" --location "$location" 2>/dev/null || \
    az rest --method DELETE --url "https://management.azure.com/subscriptions/$subscription_id/providers/Microsoft.CognitiveServices/locations/$location/deletedAccounts/$name?api-version=2023-05-01" 2>/dev/null || \
    echo "  ⚠️  Failed: $name"
done

# Key Vault
echo "Purging Key Vault..."
az keyvault list-deleted --query "[].{name:name, location:location}" -o json 2>/dev/null | \
jq -c '.[]?' | while read -r item; do
    name=$(echo "$item" | jq -r '.name')
    location=$(echo "$item" | jq -r '.location')
    echo "  Purging: $name ($location)"
    az keyvault purge --name "$name" --location "$location" 2>/dev/null || echo "  ⚠️  Failed: $name"
done

# APIM
echo "Purging API Management..."
az rest --method GET \
    --url "https://management.azure.com/subscriptions/$subscription_id/providers/Microsoft.ApiManagement/deletedservices?api-version=2022-08-01" 2>/dev/null | \
jq -c '.value[]?' | while read -r item; do
    name=$(echo "$item" | jq -r '.name')
    location=$(echo "$item" | jq -r '.location')
    echo "  Purging: $name ($location)"
    az rest --method DELETE \
        --url "https://management.azure.com/subscriptions/$subscription_id/providers/Microsoft.ApiManagement/locations/$location/deletedservices/$name?api-version=2022-08-01" \
        2>/dev/null || echo "  ⚠️  Failed: $name"
done

# Storage Account
echo "Purging Storage Account..."
az storage account list --include-deleted \
    --query "[?deletedTime != null].{name:name, location:location}" -o json 2>/dev/null | \
jq -c '.[]?' | while read -r item; do
    name=$(echo "$item" | jq -r '.name')
    location=$(echo "$item" | jq -r '.location')
    echo "  Purging: $name ($location)"
    az rest --method DELETE \
        --url "https://management.azure.com/subscriptions/$subscription_id/providers/Microsoft.Storage/locations/$location/deletedAccounts/$name?api-version=2022-09-01" \
        2>/dev/null || echo "  ⚠️  Failed: $name"
done

echo "✅ Purge complete!"
```

## Common Issues

### Permission Denied

Ensure you have the correct RBAC role assignments. The generic `Contributor` role often works, but some services require specific roles.

### Resource Not Found

Soft-deleted resources may take several minutes to appear in list commands after deletion. Wait and retry.

### Cognitive Services: "ResourceGroupParameterInvalid"

**Error**: `The resource group parameter is not valid for this operation`  
**Solution**: Remove `--resource-group` parameter from purge commands. Soft-deleted resources are no longer tied to resource groups.

```bash
# ❌ Wrong
az cognitiveservices account purge --name myopenai --location eastus --resource-group myrg

# ✅ Correct  
az cognitiveservices account purge --name myopenai --location eastus
```

### APIM: Long Purge Times

API Management instances can take 20-30 minutes to complete soft-delete. Wait before attempting purge.

### Storage: Retention Policy Conflicts

Check if storage account has legal hold or immutable blob policies that prevent purging.

### Purge Timing

Some resources have minimum retention periods before they can be purged:
- **Key Vault**: 7-90 days (configurable)
- **Storage Account**: Varies by retention policy
- **Cognitive Services**: Usually immediate
- **APIM**: Usually immediate

### Automation in CI/CD

Add purge commands to your cleanup pipelines to ensure clean deployments:

```bash
# In your cleanup step
./cleanup.sh --purge-all --yes
```

## Verification

### Test if purge fixes work

```bash
# List all soft-deleted resources to verify they exist
echo "=== Soft-deleted Cognitive Services ==="
az cognitiveservices account list-deleted -o table 2>/dev/null || echo "None found"

echo "=== Soft-deleted Key Vaults ==="  
az keyvault list-deleted -o table 2>/dev/null || echo "None found"

echo "=== Soft-deleted Storage Accounts ==="
az storage account list --include-deleted --query "[?deletedTime != null]" -o table 2>/dev/null || echo "None found"

echo "=== Soft-deleted APIM instances ==="
subscription_id=$(az account show --query "id" -o tsv)
az rest --method GET \
    --url "https://management.azure.com/subscriptions/$subscription_id/providers/Microsoft.ApiManagement/deletedservices?api-version=2022-08-01" \
    --query "value[].{name:name, location:location}" -o table 2>/dev/null || echo "None found"
```

### Test purge commands

```bash
# Test Cognitive Services purge (replace with actual values)
az cognitiveservices account purge --name <deleted-name> --location <region>

# Verify it's gone
az cognitiveservices account list-deleted --query "[?name=='<deleted-name>']" -o table
```

```yaml
- name: Purge soft-deleted resources
  run: |
    # Wait for deletion to complete
    sleep 60
    # Purge all soft-deleted resources
    bash purge-all-soft-deleted.sh
```

## Best Practices

1. **Always list before purging** to understand what will be affected
2. **Use resource group scoped purging** when possible to avoid affecting other projects
3. **Add delays** between deletion and purge operations
4. **Handle errors gracefully** in automation scripts
5. **Consider retention requirements** before purging (compliance, backup needs)
6. **Test purge scripts** in development environments first