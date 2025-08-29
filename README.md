# MCP Azure PDF Know- 🐳 **Container Ready**: Optimized for Azure Container Apps deployment

## GitHub Copilot Integration

Your MCP server is fully compatible with GitHub Copilot! The repository includes a `mcp.json` configuration file that GitHub Copilot can automatically detect and use.

### Setup

1. **Environment Variables**: Set these in your environment:
   ```bash
   MCP_SERVER_URL=https://REDACTED_CONTAINER_APP_URL/api/tools
   ```

2. **MCP Configuration**: The `mcp.json` file uses environment variables for security:
   ```json
   {
     "mcpServers": {
       "custom-pli-mcp": {
         "type": "http",
         "url": "${MCP_SERVER_URL}",
         "headers": {
           "Content-Type": "application/json"
         },
         "tools": ["search", "fetch"]
       }
     }
   }
   ```

3. **Automatic Detection**: GitHub Copilot will automatically detect and use your MCP server
4. **Ready to Use**: Ask questions about your PL/I documentation directly in GitHub Copilot Chat

### Usage Examples

```
@copilot Search for "V6R1 enhancements" in the PL/I documentation
@copilot What are the compiler options for FIXED DECIMAL optimization?
@copilot Find information about INLIST and INARRAY built-in functions
@copilot Is this PL/I code correct: DCL file-reference FILE STREAM
@copilot Look up "ORDINALNAME" built-in function usage
```

### Available Tools

- **🔍 Search Tool**: Semantic search across your indexed PDF documentation
- **📄 Fetch Tool**: Retrieve specific document content and pages

With this integration, GitHub Copilot can provide accurate answers based on your PL/I documentation!

A production-ready REST API server that connects to Azure AI Search to provide semantic search and document retrieval from indexed PDF documents. Deployed as an Azure Container App with full GitHub Copilot integration support.

## ✅ Status: **FULLY FUNCTIONAL**

The MCP server is deployed and operational with:
- ✅ **Working Search**: Returns actual document content with correct field mapping
- ✅ **GitHub Copilot Ready**: Provides structured responses for AI integration  
- ✅ **Production Deployed**: Running on Azure Container Apps
- ✅ **Authenticated Access**: Secure API key authentication

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

### 1. Setup Environment Variables

```powershell
# Copy environment template
copy .env.example .env.local

# Edit .env.local with your actual values
# - SEARCH_ENDPOINT: Your Azure AI Search URL
# - SEARCH_KEY: Your search admin key  
# - SEARCH_INDEX: Your PDF index name
# - SERVER_API_KEY: Your custom API key
```

### 2. Validate Configuration

```powershell
# Check your environment setup
./validate-env.ps1
```

### 3. Deploy to Azure

```powershell
# Deploy with your environment variables
./deploy-with-env.ps1

# Or test first with dry run
./deploy-with-env.ps1 -DryRun
```

### 4. Local Development

```powershell
# Run locally with your environment
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

### Environment Variables

All environment variables are managed locally in `.env.local` and automatically deployed to Azure Container Apps.

**Setup Process:**
1. **Copy template**: `copy .env.example .env.local`
2. **Edit values**: Fill in your actual Azure AI Search details  
3. **Validate**: `./validate-env.ps1`
4. **Deploy**: `./deploy-with-env.ps1`

**Required Variables:**

| Variable | Description | Example |
|----------|-------------|---------|
| `SEARCH_ENDPOINT` | Azure AI Search service URL | `https://mysearch.search.windows.net/` |
| `SEARCH_KEY` | Azure AI Search admin key | `1234567890ABCDEF...` |
| `SEARCH_INDEX` | Name of your PDF search index | `pdf-documents` |
| `SERVER_API_KEY` | API key for client authentication | `my-secure-api-key-123` |

📖 **See [ENV-SETUP.md](ENV-SETUP.md) for complete configuration guide.**

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