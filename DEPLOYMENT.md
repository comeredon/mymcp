# Deployment Guide for PDF Knowledge Base MCP Server

This guide walks you through deploying your MCP server that provides AI Search capabilities over your indexed PDF documents to Azure Container Apps.

## 📋 Prerequisites

### Before Deployment:
1. **PDF Documents Indexed**: Your PDF files should already be indexed in Azure AI Search
2. **Search Index Name**: Know the name of your search index (default: `pdf-index`)
3. **Azure Access**: Azure subscription with contributor access
4. **Tools Installed**:
   - Azure CLI (`az --version`)
   - Azure Developer CLI (`azd --version`) 
   - Docker Desktop (running)

## 🏗️ Environment Variables (Automatically Configured)

The deployment automatically configures these environment variables in your Azure Container App:

### **Secure Variables (Stored as Secrets):**
- `SEARCH_ENDPOINT` → Your AI Search service endpoint
- `SEARCH_KEY` → AI Search admin key  
- `SERVER_API_KEY` → Auto-generated unique API key

### **Configuration Variables:**
- `SEARCH_INDEX` → Your PDF index name (configurable)
- `PORT` → Server port (8080)

## 🚀 Deployment Options

### Option 1: Deploy to Existing Resource Group (Recommended)

```powershell
# Navigate to your project
cd "C:\Users\comeredon\OneDrive - Microsoft\Desktop\mcp-azure-pdf"

# Run deployment script
./deploy.ps1
```

This script will:
- ✅ Use your existing `mcpserver` resource group in `swedencentral`
- ✅ Create AI Search service (if needed)
- ✅ Create Container App Environment
- ✅ Build and push container image
- ✅ Deploy your MCP server

### Option 2: Deploy with Azure Developer CLI

```bash
# Initialize AZD (first time only)
azd init

# Deploy everything
azd up
```

## ⚙️ Customization

### Change Your Search Index Name

Edit `infra/main.parameters.json`:
```json
{
  "parameters": {
    "searchIndexName": {
      "value": "your-actual-index-name"
    }
  }
}
```

### Adjust Container Resources

Edit `infra/main.parameters.json`:
```json
{
  "parameters": {
    "containerAppConfig": {
      "value": {
        "cpu": "0.5",
        "memory": "1Gi", 
        "minReplicas": 1,
        "maxReplicas": 20
      }
    }
  }
}
```

## 🔍 Testing Your Deployment

### 1. Health Check
```bash
curl https://your-container-app-url.azurecontainerapps.io/health
```

### 2. Search Your PDFs
```bash
curl -X POST https://your-container-app-url.azurecontainerapps.io/api/search \
  -H "x-api-key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query": "your search term", "top": 5}'
```

### 3. Fetch Document Content
```bash
curl -X POST https://your-container-app-url.azurecontainerapps.io/api/fetch \
  -H "x-api-key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"id": "document-id"}'
```

## 📊 Finding Your API Key

After deployment, get your auto-generated API key:

```bash
# Using Azure CLI
az containerapp secret show \
  --name ca-mcp-<your-token> \
  --resource-group mcpserver \
  --secret-name server-api-key
```

## 🔧 Post-Deployment Configuration

### Update API Key (Optional)
```bash
az containerapp secret set \
  --name ca-mcp-<your-token> \
  --resource-group mcpserver \
  --secrets server-api-key="your-custom-key"
```

### Update Search Index
```bash
az containerapp update \
  --name ca-mcp-<your-token> \
  --resource-group mcpserver \
  --set-env-vars SEARCH_INDEX="new-index-name"
```

## 📈 Monitoring

### View Logs
```bash
# Real-time logs
azd logs

# Or with Azure CLI
az containerapp logs show \
  --name ca-mcp-<your-token> \
  --resource-group mcpserver \
  --follow
```

### Monitor Performance
- **Azure Portal**: Container Apps → Metrics
- **Log Analytics**: Query application logs
- **Health Check**: Monitor `/health` endpoint

## 🛠️ Troubleshooting

### Common Issues:

1. **Search Index Not Found**
   - Verify `SEARCH_INDEX` environment variable matches your actual index name
   - Check if your PDF documents are properly indexed

2. **Authentication Errors**
   - Ensure you're using the correct API key from Container App secrets
   - Verify `x-api-key` header is included in requests

3. **Container Startup Issues**
   - Check Container App logs for startup errors
   - Verify all environment variables are properly set

4. **Search Results Empty**
   - Test your search index directly in Azure Portal
   - Verify document schema matches expected fields (id, content/chunk, etc.)

## 🎯 Next Steps

1. **Integrate with Client**: Use the REST API endpoints in your applications
2. **Scale as Needed**: Adjust replica counts based on usage
3. **Monitor Usage**: Set up alerts for performance and errors
4. **Security Review**: Consider additional authentication if needed

Your PDF knowledge base MCP server is now ready to serve AI-powered search over your indexed documents! 🎉