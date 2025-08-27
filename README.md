# MCP Azure PDF Knowledge Server

A REST API server that connects to Azure AI Search to provide semantic search and document retrieval from indexed PDF documents. Designed to run as an Azure Container App.

## Features

- 🔍 **Semantic Search**: Search across indexed PDF documents using Azure AI Search
- 📄 **Document Retrieval**: Fetch full text or specific pages from PDF documents
- 🌐 **RESTful API**: Simple HTTP endpoints for integration
- � **Authentication**: API key-based authentication for security
- 📊 **Health Monitoring**: Built-in health check endpoint
- 🐳 **Container Ready**: Optimized for Azure Container Apps deployment

## Architecture

- **MCP Server**: Express.js application with MCP SDK
- **Azure AI Search**: Semantic search over PDF content
- **Azure Container Apps**: Scalable container hosting
- **Managed Identity**: Secure access to Azure services

## Quick Start

### Prerequisites

- Node.js 20+
- Azure subscription
- Azure CLI
- Azure Developer CLI (azd)

### Local Development

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Set environment variables**:
   ```bash
   export SEARCH_ENDPOINT="https://your-search-service.search.windows.net/"
   export SEARCH_KEY="your-search-admin-key"
   export SEARCH_INDEX="pdf-index"
   export SERVER_API_KEY="your-api-key"
   ```

3. **Build and run**:
   ```bash
   npm run build
   npm start
   ```

### Azure Deployment

1. **Initialize AZD**:
   ```bash
   azd auth login
   azd init
   ```

2. **Deploy to Azure**:
   ```bash
   azd up
   ```

This will:
- Create all required Azure resources (Container Apps, AI Search, Container Registry, etc.)
- Build and push the container image
- Deploy the application
- Configure security and networking

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

| Variable | Description | Required |
|----------|-------------|----------|
| `SEARCH_ENDPOINT` | Azure AI Search service endpoint | Yes |
| `SEARCH_KEY` | Azure AI Search admin key | Yes |
| `SEARCH_INDEX` | Search index name | Yes |
| `SERVER_API_KEY` | API key for client authentication | Yes |
| `PORT` | Server port (default: 8080) | No |

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