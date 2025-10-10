# Deployment Guide for MCP Azure PDF Server

This guide walks you through deploying your MCP server to Azure. The deployment creates all necessary resources automatically - no pre-deployment setup required!

## 📋 Prerequisites

**Required Tools:**
- Azure CLI (`az --version`)
- Docker Desktop (running)
- Node.js 18+ (`node --version`)

**Azure Requirements:**
- Azure subscription with contributor access
- Logged in to Azure CLI (`az login`)

## 🚀 Simple Deployment

### One-Command Deployment

```powershell
# Deploy with defaults
./deploy.ps1
```

This creates:
- ✅ Resource group (if not exists)
- ✅ Azure AI Search service (new)
- ✅ Container Apps Environment
- ✅ Container Registry
- ✅ Log Analytics Workspace
- ✅ MCP Server Container App

### Customized Deployment

```powershell
# Deploy with custom settings
./deploy.ps1 `
  -ResourceGroupName "my-mcp-rg" `
  -Location "eastus" `
  -SearchIndexName "my-pdf-index" `
  -ApiKey "my-custom-api-key"
```

**Parameters:**
- `ResourceGroupName`: Name for your resource group (default: `mcp-server-rg`)
- `Location`: Azure region (default: `swedencentral`)
- `EnvironmentName`: Environment identifier (default: `mcp`)
- `SearchIndexName`: Name for your search index (default: `pdf-index`)
- `ApiKey`: Custom API key (default: auto-generated)

## ⚙️ What Gets Created

The deployment creates these Azure resources:

1. **Resource Group**: Container for all resources
2. **Azure AI Search Service**: For PDF document indexing and search
   - SKU: Basic (can be changed in infra/main.bicep)
   - Semantic search: Free tier enabled
3. **Container Apps Environment**: Hosts the MCP server
4. **Container Registry**: Stores Docker images
5. **Log Analytics Workspace**: Application monitoring
6. **Managed Identity**: Secure service-to-service authentication
7. **MCP Server Container App**: Your deployed application

## 📝 After Deployment

### 1. Index Your PDF Documents

The deployment creates an Azure AI Search service, but you need to populate it with your PDF documents:

**Using Azure Portal:**
1. Go to Azure Portal → Search Service
2. Click "Import data" wizard
3. Connect your PDF data source (Azure Blob Storage, etc.)
4. Use Azure AI Document Intelligence for PDF extraction
5. Create index with the name you specified (default: `pdf-index`)

**Required Index Schema:**
Your index should include these fields:
- `id`: Document identifier (string, key)
- `content` or `chunk`: Text content (string, searchable)
- `metadata_storage_name`: File name (optional)
- `metadata_storage_path`: File path (optional)

### 2. Test Your Deployment

Use the values from the deployment output:

```powershell
# Health check (no auth required)
curl https://your-mcp-server-url/health

# Search endpoint (requires API key)
curl -X POST https://your-mcp-server-url/api/search `
  -H "x-api-key: YOUR_API_KEY" `
  -H "Content-Type: application/json" `
  -d '{"query": "test search", "top": 5}'
```

### 3. Configure Your Client

Use the deployment outputs to configure your GitHub Copilot or other MCP client:

```json
{
  "mcpServers": {
    "pdf-server": {
      "type": "http",
      "url": "https://your-mcp-server-url/api/tools",
      "headers": {
        "x-api-key": "YOUR_API_KEY"
      }
    }
  }
}
```

## 📊 Monitoring

### View Application Logs
```powershell
# Get logs from Azure Portal or CLI
az containerapp logs show `
  --name <container-app-name> `
  --resource-group <resource-group-name> `
  --follow
```

### Monitor Performance
- **Azure Portal**: Navigate to Container Apps → Metrics
- **Log Analytics**: Query application logs and metrics
- **Health Endpoint**: Monitor `/health` for service availability

## 🛠️ Troubleshooting

### Common Issues

**1. Search returns no results**
- Verify your search index is created and populated
- Check index name matches deployment parameter
- Test search directly in Azure Portal

**2. Container fails to start**
- Check container logs for error messages
- Verify Docker image built successfully
- Ensure all environment variables are set

**3. Authentication fails**
- Use the API key from deployment output
- Verify `x-api-key` header is included in requests
- Check key hasn't been changed in Azure Portal

**4. Can't access MCP server URL**
- Verify Container App is running in Azure Portal
- Check ingress is enabled and set to external
- Wait a few minutes after deployment for DNS propagation

### Getting Help

Check logs for detailed error messages:
```powershell
az containerapp logs show --name <app-name> --resource-group <rg-name> --tail 50
```

## 🎯 Next Steps

1. **Index Your PDFs**: Populate Azure AI Search with your documents
2. **Test Thoroughly**: Verify search results match expectations
3. **Integrate Clients**: Configure GitHub Copilot or other MCP clients
4. **Monitor Usage**: Set up alerts and review logs regularly
5. **Scale as Needed**: Adjust container resources based on usage

Your MCP server is now deployed and ready to serve AI-powered search! 🎉