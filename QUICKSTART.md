# 🚀 Quick Start Guide

## Prerequisites (2 minutes)
```powershell
# 1. Check you have everything
az --version      # Azure CLI
docker --version  # Docker Desktop
node --version    # Node.js 20+

# 2. Login to Azure
az login
```

## Deploy (5 minutes)

### Option A: Default Deployment
```powershell
./deploy.ps1
```

### Option B: Custom Deployment
```powershell
./deploy.ps1 `
  -ResourceGroupName "my-mcp" `
  -Location "eastus" `
  -EnvironmentName "prod"
```

### Option C: Azure Developer CLI
```powershell
azd up
```

> **Note:** By default, deployment includes API Management (APIM) gateway for production security. The Container App runs internally and is only accessible through APIM.

## Post-Deployment (10 minutes)

### 1. Save Outputs
The script will display:
- ✅ **MCP Public Endpoint** (APIM Gateway URL) - Use this!
- ✅ APIM Gateway URL
- ✅ Container App Internal URL (not accessible externally)
- ✅ Storage Account Name
- ✅ Search Service Name
- ✅ AI Foundry Endpoint

### 2. Upload PDFs
```powershell
az storage blob upload-batch `
  -d pdfs `
  -s ./my-pdfs `
  --account-name <storage-account-name>
```

### 3. Create Search Index
- Go to Azure Portal → AI Search Service
- Create index named `pdf-index`
- Use Azure AI Document Intelligence
- Index your uploaded PDFs

### 4. Test
```powershell
# Health check (use APIM public endpoint)
curl https://<apim-gateway-url>/mcp/health

# Search test (authentication handled by APIM)
curl -X POST https://<apim-gateway-url>/mcp/api/search `
  -H "Content-Type: application/json" `
  -d '{"query": "test", "top": 5}'
```

> **Important:** Always use the APIM gateway URL, not the Container App URL. The Container App is internal-only.

### 5. Configure Client
Update `mcp.json`:
```json
{
  "mcpServers": {
    "custom-pli-mc": {
      "url": "https://<apim-gateway-url>/mcp/api/tools"
    }
  }
}
```

> **Note:** Do **not** include `x-api-key` header. Authentication is handled automatically by APIM policies.

## Resources Created

**Core Services:**
- Container App (MCP Server - internal only)
- Container Registry
- AI Search
- Storage Account
- Azure AI Foundry
- Log Analytics
- Managed Identity
- **API Management (APIM Gateway - public endpoint)**

**Optional:**
- Virtual Network (with `-DeployVNet`)

**Security Architecture:**
```
Copilot → APIM Gateway (public) → Container App (internal) → Azure Services
```

## Quick Commands

```powershell
# View logs
az containerapp logs show --name <app> --resource-group <rg> --tail 50

# List resources
az resource list --resource-group <rg> --output table

# Restart container
az containerapp revision restart --name <app> --resource-group <rg>

# Update container
docker build -t <acr>.azurecr.io/mcp-azure-pdf:latest .
docker push <acr>.azurecr.io/mcp-azure-pdf:latest
az containerapp update --name <app> --resource-group <rg>
```

## Default Parameters

| Setting | Default Value |
|---------|---------------|
| Resource Group | `mcp-server-rg` |
| Location | `swedencentral` |
| Environment | `mcp` |
| Search Index | `pdf-index` |
| Container CPU | `0.25` |
| Container Memory | `0.5Gi` |
| Min Replicas | `1` |
| Max Replicas | `10` |

## Cost Estimate

**Basic Deployment:**
- Container Apps: ~$5-20/month
- AI Search (Basic): ~$75/month
- Storage: ~$2/month
- Azure AI Foundry: Pay per use
- Container Registry: ~$5/month
- **APIM (Consumption): ~$0.035 per 10K calls**
- **Total: ~$87-102/month + AI Foundry usage + APIM usage**

## Support

- 📋 Full guide: [DEPLOYMENT.md](./DEPLOYMENT.md)
- ✅ Checklist: [DEPLOYMENT_CHECKLIST.md](./DEPLOYMENT_CHECKLIST.md)
- 🤝 Sharing: [SHARING.md](./SHARING.md)
- 📊 Review: [REVIEW_SUMMARY.md](./REVIEW_SUMMARY.md)

## Troubleshooting

**Container won't start:**
```powershell
az containerapp logs show --name <app> --resource-group <rg>
```

**Search returns no results:**
- Verify index is created
- Check documents are indexed
- Test search in Azure Portal

**Authentication fails:**
- APIM handles authentication automatically
- Do not include `x-api-key` header in client requests
- Verify APIM policy is configured correctly

**Can't access endpoint:**
- Use APIM gateway URL, not Container App URL
- Container App is internal-only for security
- Verify APIM is deployed and running

**Need help?**
- Check container logs
- Review Azure Portal → Resource Group
- Use deployment checklist
