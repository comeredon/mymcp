---
name: wsl2-cleanup
description: Tear down all Azure resources created by deploy.sh for the MCP Azure PDF Server. Use this skill to clean up a deployment from Ubuntu running in WSL2, including purging soft-deleted resources so names can be reused.
---

# Cleanup — MCP Azure PDF Server on WSL2

## Overview

This skill removes all Azure resources deployed by `deploy.sh` and purges soft-deleted resources (Azure OpenAI, APIM) so resource names can be reused immediately.

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- `jq` installed
- The resource group name used during deployment (default: `mcp-server-rg`)

## 1. Verify Azure Login

```bash
az account show --query "{user:user.name, subscription:name}" -o table
```

If not logged in:

```bash
az login
```

## 2. Review Resources Before Cleanup

List all resources that will be deleted:

```bash
az resource list --resource-group mcp-server-rg \
    --query "[].{Name:name, Type:type}" -o table
```

## 3. Run the Cleanup Script

### Basic cleanup (delete resource group only)

```bash
bash cleanup.sh --yes
```

### Full cleanup (delete + purge soft-deleted resources)

Recommended when you plan to redeploy with the same resource names:

```bash
bash cleanup.sh --purge-all --yes
```

### Custom resource group

```bash
bash cleanup.sh --resource-group my-custom-rg --purge-all --yes
```

### Interactive mode (requires typing resource group name to confirm)

```bash
bash cleanup.sh --purge-all
```

## 4. Script Options Reference

| Flag | Description |
|------|-------------|
| `--resource-group NAME` | Resource group to delete (default: `mcp-server-rg`) |
| `--purge-cognitive` | Purge soft-deleted Azure OpenAI / Cognitive Services resources |
| `--purge-apim` | Purge soft-deleted API Management instances |
| `--purge-all` | Purge all soft-deleted resources (cognitive + APIM) |
| `--yes` | Skip confirmation prompt |
| `-h, --help` | Show help message |

## 5. Verify Cleanup

After the script completes, verify the resource group is gone:

```bash
az group show --name mcp-server-rg 2>/dev/null && echo "⚠️ Still exists" || echo "✅ Deleted"
```

Check for remaining soft-deleted resources:

```bash
# Cognitive Services / OpenAI
az cognitiveservices account list-deleted -o table

# APIM
az rest --method GET \
    --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/providers/Microsoft.ApiManagement/deletedservices?api-version=2022-08-01" \
    | jq '.value[] | {name, location}'
```

## 6. What Gets Deleted

| Resource | Behavior |
|----------|----------|
| Resource Group | Deleted (all resources inside removed) |
| Container Registry (ACR) | Deleted with group |
| Container App + Environment | Deleted with group |
| Azure AI Search | Deleted with group |
| Storage Account | Deleted with group (blobs lost) |
| Azure OpenAI | Soft-deleted → purged with `--purge-cognitive` |
| API Management | Soft-deleted → purged with `--purge-apim` |
| Managed Identity + Roles | Deleted with group |
| Log Analytics | Deleted with group |
| VNet (if deployed) | Deleted with group |

## 7. Troubleshooting

### Resource group stuck in "Deleting" state

Some resources (especially APIM) take 10–15 minutes to delete. Wait and retry:

```bash
az group wait --name mcp-server-rg --deleted --timeout 900
```

### "Name already in use" on redeployment

Cognitive Services and APIM use soft-delete by default. Use `--purge-all` to free the names:

```bash
bash cleanup.sh --purge-all --yes
```

### Permission errors during purge

You need `Contributor` or `Owner` role on the subscription to purge soft-deleted resources.

## 8. Redeploy After Cleanup

Once cleanup is complete, redeploy from scratch:

```bash
bash deploy.sh --deploy-apim
```

Or use the DevOps agent:

```
@DevOpsAgent setup WSL2 and deploy MCP Azure PDF Server
```
