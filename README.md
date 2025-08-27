# MCP Azure PDF Knowledge Server

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

### MCP Tools

The server provides two main tools:

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