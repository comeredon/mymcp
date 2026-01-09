# Deployment Guide for MCP Azure PDF Server

This guide walks you through deploying your MCP server to Azure. The deployment creates all necessary resources automatically - no pre-deployment setup required!

## 📋 Prerequisites

**Required Tools:**
- Azure CLI (`az --version`)
- Docker Desktop (running)
- Node.js 20+ (`node --version`)

**Azure Requirements:**
- Azure subscription with contributor access
- Permissions to create:
  - Resource Groups
  - Container Apps and Container Registry
  - AI Search, Storage Accounts, Azure OpenAI
  - Managed Identities and Role Assignments
  - (Optional) API Management and Virtual Networks
- Logged in to Azure CLI (`az login`)

## 🚀 Simple Deployment

### One-Command Deployment

```powershell
# Deploy with defaults
./deploy.ps1
```

This creates:
- ✅ Resource group (if not exists)
- ✅ Azure AI Search service
- ✅ Storage Account (for PDF blobs)
- ✅ Azure OpenAI (with embeddings & chat models)
- ✅ Container Apps Environment
- ✅ Container Registry
- ✅ Log Analytics Workspace
- ✅ Managed Identity (with RBAC roles)
- ✅ MCP Server Container App

### Customized Deployment

```powershell
# Deploy with custom settings
./deploy.ps1 `
  -ResourceGroupName "my-mcp-rg" `
  -Location "eastus" `
  -SearchIndexName "my-pdf-index" `
  -ApiKey "my-custom-api-key" `
  -ApimPublisherEmail "admin@example.com" `
  -ApimPublisherName "MyOrg" `
  -DeployVNet
```

**Parameters:**
- `ResourceGroupName`: Name for your resource group (default: `mcp-server-rg`)
- `Location`: Azure region (default: `swedencentral`)
- `EnvironmentName`: Environment identifier (default: `mcp`)
- `SearchIndexName`: Name for your search index (default: `pdf-index`)
- `ApiKey`: Custom API key (default: auto-generated)
- `ApimPublisherEmail`: APIM publisher email (default: `admin@contoso.com`)
- `ApimPublisherName`: APIM publisher name (default: `Contoso`)
- `DeployVNet`: Deploy Virtual Network (default: `false`)

> **Note:** API Management (APIM) is deployed by default for production use. APIM provides a secure gateway with the Container App running internally (not exposed to the internet).

## ⚙️ What Gets Created

The deployment creates these Azure resources:

1. **Resource Group**: Container for all resources
2. **Azure AI Search Service**: For PDF document indexing and search
   - SKU: Basic (configurable)
   - Semantic search: Free tier enabled
3. **Storage Account**: For storing PDF documents
   - Containers: `pdfs`, `documents`
   - Standard LRS (configurable)
4. **Azure OpenAI**: For RAG (Retrieval Augmented Generation)
   - Deployment: `embeddings` (text-embedding-3-large) - Modern, cost-effective, 3072 dimensions
   - Deployment: `chat` (gpt-4o 2024-08-06) - With vision capabilities for image/chart analysis
5. **Container Apps Environment**: Hosts the MCP server
   - Integrated with Log Analytics
6. **Container Registry**: Stores Docker images
7. **Log Analytics Workspace**: Application monitoring
8. **Managed Identity**: Secure service-to-service authentication
   - Roles: Search Index Data Contributor
   - Roles: Storage Blob Data Contributor
   - Roles: Cognitive Services OpenAI User
   - Roles: ACR Pull
9. **MCP Server Container App**: Your deployed application (internal-only)
   - **Security:** Not exposed to internet, only accessible through APIM gateway
10. **API Management**: API gateway (default: enabled)
    - **Public endpoint** for external access
    - **Automatic API key injection** via policies
    - **Backend connection** to internal Container App
    - **Security:** Only public-facing component
11. **Virtual Network** (optional): Private networking

### Security Architecture

```
External Clients (Copilot, etc.)
         ↓
   [APIM Gateway] ← Public access point
         ↓
  [Container App] ← Internal only (no external access)
         ↓
  [Azure Services] ← Search, Storage, OpenAI
```

- Container App has **internal ingress only** - not accessible from internet
- All external traffic **must** go through APIM gateway
- APIM policies automatically inject API key for authentication
- Managed Identity used for Container App → Azure Services communication

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

Use the **APIM public endpoint** from the deployment output:

```powershell
# Health check (no auth required)
curl https://your-apim-gateway-url/mcp/health

# Search endpoint (auth handled by APIM)
curl -X POST https://your-apim-gateway-url/mcp/api/search `
  -H "Content-Type: application/json" `
  -d '{"query": "test search", "top": 5}'
```

> **Important:** Use the APIM gateway URL, **not** the Container App internal URL. The Container App is not accessible from the internet.

### 3. Configure Your Client

Use the **APIM MCP API endpoint** to configure your GitHub Copilot or other MCP client:

```json
{
  "mcpServers": {
    "custom-pli-mc": {
      "url": "https://your-apim-gateway-url/mcp/api/tools"
    }
  }
}
```

> **Note:** Authentication is handled automatically by APIM. Do **not** include the `x-api-key` header in your client configuration.

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
- Use the **APIM gateway URL**, not the Container App URL
- Container App is internal-only and not accessible from internet
- Verify APIM is deployed (check deployment output)
- Check APIM is running in Azure Portal
- Wait a few minutes after deployment for APIM configuration

**5. APIM returns 401/403 errors**
- Verify APIM named values contain correct API key
- Check APIM policy is correctly configured
- Review APIM diagnostics in Azure Portal

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