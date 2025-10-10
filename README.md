# MCP Azure PDF Knowledge Server

## GitHub Copilot Integration

Your MCP server is fully compatible with GitHub Copilot! After deployment, configure GitHub Copilot to use your MCP server.

### Setup

1. **Get deployment outputs** from the deploy.ps1 script (MCP Server URL and API Key)

2. **Update mcp.json** with your deployment details:
   ```json
   {
     "mcpServers": {
       "pdf-search": {
         "type": "http",
         "url": "https://your-actual-server-url.azurecontainerapps.io/api/tools",
         "headers": {
           "x-api-key": "your-actual-api-key",
           "Content-Type": "application/json"
         },
         "tools": ["search", "fetch"]
       }
     }
   }
   ```

3. **Use with GitHub Copilot Chat**:
   ```
   @copilot Search for "performance optimization" in my PDF documentation
   @copilot What does the documentation say about configuration?
   @copilot Find information about installation procedures
   ```

### Available Tools

- **🔍 Search Tool**: Semantic search across your indexed PDF documentation
- **📄 Fetch Tool**: Retrieve specific document content and pages

A production-ready REST API server that connects to Azure AI Search to provide semantic search and document retrieval from indexed PDF documents. Deployed as an Azure Container App with full GitHub Copilot integration support.

## ✨ Simplified Deployment

**No pre-deployment setup required!** Simply run `./deploy.ps1` and it will:
- ✅ Create all Azure resources automatically (Search service, Container Apps, etc.)
- ✅ Build and deploy your Docker container
- ✅ Generate secure credentials
- ✅ Provide complete deployment outputs

Just login to Azure, run the script, and you're ready to index your PDFs!

## Features

- 🔍 **Semantic Search**: Search across indexed PDF documents using Azure AI Search
- 📄 **Document Retrieval**: Fetch full text or specific pages from PDF documents
- 🤖 **GitHub Copilot Integration**: MCP-compatible endpoints for AI assistance
- 🌐 **RESTful API**: Simple HTTP endpoints for integration
- 🔐 **Authentication**: API key-based authentication for security
- 📊 **Health Monitoring**: Built-in health check endpoint
- 🐳 **Container Ready**: Optimized for Azure Container Apps deploymentPDF Knowledge Server

A REST API server that connects to Azure AI Search to provide semantic search and document retrieval from indexed PDF documents. Designed to run as an Azure Container App.

## Features

- 🔍 **Semantic Search**: Search across indexed PDF documents using Azure AI Search
- 📄 **Document Retrieval**: Fetch full text or specific pages from PDF documents
- 🌐 **RESTful API**: Simple HTTP endpoints for integration
- � **Authentication**: API key-based authentication for security
- 📊 **Health Monitoring**: Built-in health check endpoint
- 🐳 **Container Ready**: Optimized for Azure Container Apps deployment

## Quick Start

### 1. Prerequisites

- Azure CLI (`az --version`)
- Docker Desktop (running)
- Node.js 18+ (`node --version`)

### 2. Deploy to Azure

```powershell
# Login to Azure
az login

# Deploy everything (creates all resources)
./deploy.ps1

# Or customize deployment
./deploy.ps1 -ResourceGroupName "my-rg" -Location "eastus" -SearchIndexName "my-index"
```

The deployment will:
- ✅ Create a new resource group (or use existing)
- ✅ Deploy Azure AI Search service
- ✅ Deploy Container Apps infrastructure
- ✅ Build and push Docker image
- ✅ Deploy MCP server container

### 3. Index Your PDF Documents

After deployment, go to Azure Portal and:
1. Navigate to your Azure AI Search service
2. Create an index named 'pdf-index' (or the name you specified)
3. Index your PDF documents using Azure AI Document Intelligence or custom indexing

### 4. Test Your Deployment

```powershell
# Test health endpoint
curl https://your-container-app-url.azurecontainerapps.io/health

# Test search (use API key from deployment output)
curl -X POST https://your-container-app-url.azurecontainerapps.io/api/search `
  -H "x-api-key: YOUR_API_KEY" `
  -H "Content-Type: application/json" `
  -d '{"query": "test", "top": 5}'
```

### 5. Local Development (Optional)

```powershell
# Copy deployment outputs to .env.local
copy .env.example .env.local
# Edit .env.local with values from deployment output

# Run locally
npm run dev-local
```

## API Endpoints

### Health Check
```
GET /health
```
Returns service health status (no authentication required).

### Search Endpoint  
```
POST /api/search
Headers: x-api-key: YOUR_API_KEY
Content-Type: application/json

{
  "query": "your search query",
  "top": 5
}
```

### Tools Endpoint (GitHub Copilot Integration)
```
POST /api/tools  
Headers: x-api-key: YOUR_API_KEY
Content-Type: application/json

{
  "tool": "search",
  "arguments": {
    "query": "your search query", 
    "top": 5
  }
}
```

### Fetch Endpoint
```
POST /api/fetch
Headers: x-api-key: YOUR_API_KEY
Content-Type: application/json

{
  "id": "document-id",
  "pages": [1, 2, 3]
}
```

## Working Example

**Question:** "What are the enhancements from V6R1?"

**Response:** Returns comprehensive information about PL/I V6R1 enhancements including:
- Performance improvements for FIXED DECIMAL and PICTURE variables
- New hardware instruction utilization
- Enhanced compiler options (BASE64, HEXDECODE, NOPUT, DCLS suboptions)
- Better storage problem detection
- ZLIB compression samples

## MCP Tools

The server provides GitHub Copilot-compatible tools:

#### 1. Search Tool
Search for relevant PDF content:
```json
{
  "name": "search",
  "arguments": {
    "query": "your search query",
    "top": 5
  }
}
```

#### 2. Fetch Tool
Retrieve full document or specific pages:
```json
{
  "name": "fetch",
  "arguments": {
    "id": "document-id",
    "pages": [1, 2, 3]
  }
}
```

## Configuration

The deployment automatically creates and configures all necessary resources. You don't need to set up environment variables before deployment!

### Deployment Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `ResourceGroupName` | `mcp-server-rg` | Azure resource group name |
| `Location` | `swedencentral` | Azure region |
| `EnvironmentName` | `mcp` | Environment identifier |
| `SearchIndexName` | `pdf-index` | Name for your PDF search index |
| `ApiKey` | Auto-generated | Custom API key (optional) |

### Post-Deployment Configuration

After deployment, you'll receive all connection details including:
- Azure AI Search endpoint and credentials
- MCP Server URL
- Generated API key

Use these values to:
1. Index your PDF documents in Azure AI Search
2. Configure your client applications
3. Set up local development environment (if needed)

### Azure Resources

The deployment creates:

- **Resource Group**: Contains all resources
- **Container Apps Environment**: Hosts the container
- **Container Registry**: Stores container images
- **AI Search Service**: Provides search capabilities
- **Log Analytics**: Application monitoring
- **Managed Identity**: Secure service authentication

## Security

- ✅ **Managed Identity**: No hardcoded credentials
- ✅ **RBAC**: Least privilege access
- ✅ **API Authentication**: Required for all MCP endpoints
- ✅ **HTTPS**: Encrypted communication
- ✅ **Container Security**: Non-root user

## Scaling

The container app automatically scales based on:
- HTTP requests
- CPU/Memory usage
- Custom metrics

Configure scaling in `infra/main.bicep`:
```bicep
param containerAppConfig object = {
  cpu: '0.25'
  memory: '0.5Gi'
  minReplicas: 1
  maxReplicas: 10
}
```

## Monitoring

- **Health Checks**: Built-in health endpoint
- **Log Analytics**: Centralized logging
- **Azure Monitor**: Metrics and alerts
- **Container Insights**: Container performance

## Development

### Project Structure
```
├── src/
│   └── server.ts          # Main MCP server
├── infra/                 # Bicep templates
│   ├── main.bicep
│   └── core/             # Reusable modules
├── Dockerfile
├── azure.yaml            # AZD configuration
└── package.json
```

### Build Commands

```bash
# Development
npm run dev

# Production build
npm run build
npm start

# Clean build artifacts
npm run clean
```

## Troubleshooting

### Common Issues

1. **Search Service Connection**: Verify endpoint and key
2. **Container Startup**: Check environment variables
3. **Authentication**: Ensure API key is correct
4. **Index Not Found**: Verify search index exists

### Logs

View application logs:
```bash
azd logs
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

MIT License