# MCP Azure PDF Knowledge Server

A production-ready, secure REST API server that provides semantic search and document retrieval from indexed PDF documents. Deployed on Azure with enterprise-grade security using API Management as a gateway.

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Azure Subscription                               │
│                                                                          │
│  ┌────────────────────┐                                                 │
│  │  GitHub Copilot    │                                                 │
│  │  or MCP Client     │                                                 │
│  └─────────┬──────────┘                                                 │
│            │ HTTPS                                                       │
│            │                                                            │
│  ┌─────────▼──────────────────────────────────────────────────┐        │
│  │          Azure API Management (APIM)                        │        │
│  │  ┌──────────────────────────────────────────────────┐      │        │
│  │  │  MCP API Endpoints:                              │      │        │
│  │  │  • /mcp/health          (no auth)               │      │        │
│  │  │  • /mcp/api/tools       (auth via policy)       │      │        │
│  │  │  • /mcp/api/search      (auth via policy)       │      │        │
│  │  │  • /mcp/api/fetch       (auth via policy)       │      │        │
│  │  └──────────────────────────────────────────────────┘      │        │
│  │                                                              │        │
│  │  Security: API Key injection via policy                     │        │
│  │  Benefits: Rate limiting, monitoring, caching               │        │
│  └──────────────────────┬───────────────────────────────────────┘        │
│                         │ Internal Network                               │
│                         │                                               │
│  ┌──────────────────────▼────────────────────────────────────┐          │
│  │      Container Apps Environment (Internal Only)           │          │
│  │  ┌────────────────────────────────────────────────┐       │          │
│  │  │   MCP Server Container App                     │       │          │
│  │  │   • Express.js REST API                        │       │          │
│  │  │   • Node.js 20 + TypeScript                    │       │          │
│  │  │   • No direct external access                  │       │          │
│  │  │   • Managed Identity authentication            │       │          │
│  │  └────────┬───────────────────────┬────────────────┘       │          │
│  └───────────┼───────────────────────┼─────────────────────────┘          │
│              │                       │                                   │
│              │ Managed Identity      │ Managed Identity                  │
│              │                       │                                   │
│  ┌───────────▼──────────┐   ┌───────▼──────────┐   ┌──────────────┐   │
│  │  Azure AI Search     │   │  Storage Account │   │ Azure OpenAI │   │
│  │  ┌────────────────┐  │   │  ┌────────────┐  │   │  ┌────────┐  │   │
│  │  │ PDF Index      │  │   │  │ Blob:      │  │   │  │ GPT-4o │  │   │
│  │  │ Semantic       │  │   │  │ Documents  │  │   │  │ Vision │  │   │
│  │  │ • Embeddings   │  │   │  │ • pdfs     │  │   │  │ Embed  │  │   │
│  │  │ • Semantic     │  │   │  │ • documents│  │   │  └────────┘  │   │
│  │  │   Search       │  │   │  └────────────┘  │   │              │   │
│  │  └────────────────┘  │   └──────────────────┘   └──────────────┘   │
│  └──────────────────────┘                                              │
│                                                                         │
│  ┌──────────────────────┐   ┌──────────────────────┐                  │
│  │  Log Analytics       │   │  Container Registry  │                  │
│  │  • Application Logs  │   │  • Docker Images     │                  │
│  │  • APIM Logs         │   │  • ACR Pull via MI   │                  │
│  │  • Monitoring        │   └──────────────────────┘                  │
│  └──────────────────────┘                                              │
│                                                                         │
│  Security: Managed Identity + RBAC + Key Vault                         │
└─────────────────────────────────────────────────────────────────────────┘

Key Security Features:
✅ Container App is INTERNAL ONLY - no direct external access
✅ All traffic flows through API Management gateway
✅ API keys managed securely via APIM policies
✅ Managed Identity for service-to-service authentication
✅ RBAC (Role-Based Access Control) for all Azure resources
✅ TLS/HTTPS enforced on all endpoints
```

## 🔒 Security Architecture

### Multi-Layer Security

1. **API Management (Gateway)**
   - Public-facing endpoint
   - API key injection via policies
   - Rate limiting and throttling
   - Request/response transformation
   - Monitoring and logging

2. **Container App (Internal)**
   - No external ingress
   - Only accessible from APIM within Azure network
   - Managed Identity authentication
   - No hardcoded credentials

3. **Data Services**
   - Managed Identity authentication (no keys)
   - RBAC for fine-grained access control
   - Network security via service endpoints
   - Encryption at rest and in transit

## ✨ Features

- 🔍 **Semantic Search**: AI-powered search across indexed PDF documents using Azure AI Search
- 📄 **Document Retrieval**: Fetch full text or specific pages from PDF documents
- 🤖 **GitHub Copilot Integration**: MCP-compatible endpoints for AI assistance
- 🛡️ **Enterprise Security**: API Management gateway with managed identity authentication
- 🌐 **RESTful API**: Simple HTTP endpoints with comprehensive documentation
- 📊 **Monitoring**: Built-in health checks, logging, and Azure Monitor integration
- 🔐 **Zero Trust**: Internal-only container app, all access via APIM gateway
- ⚡ **Auto-scaling**: Automatic scaling based on demand
- 🐳 **Container-based**: Deployed on Azure Container Apps for reliability

## GitHub Copilot Integration

### Setup

1. **Deploy** the infrastructure using the deployment script
2. **Get** the API Management URL from deployment outputs
3. **Update** your `mcp.json`:
   ```json
   {
     "mcpServers": {
       "pdf-search-mcp": {
         "type": "http",
         "url": "https://your-apim-gateway.azure-api.net/mcp/api/tools",
         "headers": {
           "Content-Type": "application/json"
         },
         "tools": ["search", "fetch"]
       }
     }
   }
   ```

4. **Use** with GitHub Copilot Chat:
   ```
   @copilot Search for "performance optimization" in my PDF documentation
   @copilot What does the documentation say about configuration?
   @copilot Find information about installation procedures
   ```

### Available Tools

- **🔍 search** - Semantic search across indexed PDF documents
- **📄 fetch** - Retrieve specific document content and pages

## Quick Start

### 1. Prerequisites

- Azure CLI (`az --version`)
- Docker Desktop (running)
- Node.js 20+ (`node --version`)
- Azure subscription with Contributor access

### 2. Deploy to Azure

```powershell
# Login to Azure
az login

# Deploy everything (creates all resources)
./deploy.ps1 -ApimPublisherEmail "admin@yourdomain.com" -ApimPublisherName "YourOrg"

# Or customize deployment
./deploy.ps1 `
  -ResourceGroupName "my-rg" `
  -Location "eastus" `
  -ApimPublisherEmail "admin@yourdomain.com" `
  -ApimPublisherName "YourOrg"
```

The deployment will create:
- ✅ Resource group (or use existing)
- ✅ API Management gateway (public endpoint)
- ✅ Container App (internal only)
- ✅ Container Apps Environment
- ✅ Container Registry
- ✅ Azure AI Search
- ✅ Storage Account
- ✅ Azure OpenAI
- ✅ Log Analytics
- ✅ Managed Identity with RBAC roles

**Important:** The Container App is deployed as **internal only**. All external access must go through API Management for security.

### 3. Index Your PDF Documents

After deployment, go to Azure Portal and:
1. Navigate to your Azure AI Search service
2. Create an index named 'pdf-index' (or the name you specified)
3. Index your PDF documents using Azure AI Document Intelligence or custom indexing

### 4. Test Your Deployment

```powershell
# Get APIM Gateway URL from deployment output
$apimUrl = "<your-apim-gateway-url>"  # e.g., https://apim-xxxxx.azure-api.net

# Test health endpoint (no auth required)
curl "$apimUrl/mcp/health"

# Test MCP tools endpoint
curl -X POST "$apimUrl/mcp/api/tools" `
  -H "Content-Type: application/json" `
  -d '{"tool": "search", "arguments": {"query": "test", "top": 5}}'

# Test search endpoint directly
curl -X POST "$apimUrl/mcp/api/search" `
  -H "Content-Type: application/json" `
  -d '{"query": "test", "top": 5}'
```

**Note:** API authentication is handled automatically by APIM policies. No API key header required from clients.

### 5. Configure GitHub Copilot

Update your `mcp.json` with the APIM URL from deployment outputs:

```json
{
  "mcpServers": {
    "pdf-search-mcp": {
      "type": "http",
      "url": "https://your-apim-gateway.azure-api.net/mcp/api/tools",
      "headers": {
        "Content-Type": "application/json"
      }
    }
  }
}
```

## API Endpoints

All endpoints are accessed through API Management. The base URL is: `https://<your-apim-gateway>.azure-api.net/mcp`

### Health Check
```
GET /mcp/health
```
Returns service health status. No authentication required.

**Response:**
```json
{
  "status": "healthy"
}
```

### MCP Tools Endpoint (for GitHub Copilot)
```
POST /mcp/api/tools
Content-Type: application/json

{
  "tool": "search",
  "arguments": {
    "query": "your search query",
    "top": 5
  }
}
```

**Available Tools:**
- `search` - Semantic search across PDF documents
- `fetch` - Retrieve specific document or pages

### Search Endpoint
```
POST /mcp/api/search
Content-Type: application/json

{
  "query": "your search query",
  "top": 5
}
```

### Fetch Endpoint
```
POST /mcp/api/fetch
Content-Type: application/json

{
  "id": "document-id",
  "pages": [1, 2, 3]
}
```

**Note:** API authentication is handled by APIM policies. The API key is injected automatically - no client-side authentication headers required.

## Configuration

### Two Types of Configuration Files

This repository contains two separate configuration file systems:

#### 1. Local Development (`.env.example` → `.env.local`)
For running the MCP server locally on your development machine:
- Copy `.env.example` to `.env.local`
- Fill in values from your Azure resources
- Used by `npm run dev-local`

#### 2. Azure Deployment (`.azure/mcp/.env`)
For deploying to Azure using Azure Developer CLI:
- Configure deployment settings (region, environment name, etc.)
- Used by `azd up` and `./deploy.ps1`
- No secrets - only deployment configuration

These serve different purposes and do not conflict.

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
│   └── server.ts                      # Main MCP server application
├── infra/                             # Infrastructure as Code (Bicep)
│   ├── main.bicep                    # Main deployment template
│   ├── abbreviations.json            # Resource naming conventions
│   └── core/                         # Reusable Bicep modules
│       ├── ai/
│       │   └── cognitiveservices.bicep
│       ├── gateway/
│       │   └── apim.bicep
│       ├── host/
│       │   ├── container-app.bicep
│       │   ├── container-apps-environment.bicep
│       │   └── container-registry.bicep
│       ├── monitor/
│       │   └── loganalytics.bicep
│       ├── network/
│       │   └── vnet.bicep
│       ├── search/
│       │   └── search-services.bicep
│       ├── security/
│       │   ├── managed-identity.bicep
│       │   └── role.bicep
│       └── storage/
│           └── storage-account.bicep
├── .azure/                           # Azure Developer CLI config
│   ├── .env.template
│   └── mcp/
│       └── .env
├── Dockerfile                        # Container definition
├── azure.yaml                        # AZD configuration
├── package.json                      # Node.js dependencies
├── tsconfig.json                     # TypeScript configuration
├── deploy.ps1                        # PowerShell deployment script
├── validate-deployment.ps1           # Deployment validation script
├── DEPLOYMENT.md                     # Detailed deployment guide
├── DEPLOYMENT_CHECKLIST.md           # Validation checklist
├── QUICKSTART.md                     # Quick reference guide
├── SHARING.md                        # Guide for sharing this repo
├── mcp.json                          # MCP client configuration template
└── .env.example                      # Environment variables template
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
# or
az containerapp logs show --name <app-name> --resource-group <rg-name> --tail 50
```

### Validation

Use the validation script to check your deployment:
```powershell
.\validate-deployment.ps1 -ResourceGroupName <your-rg-name>
```

## Documentation

- 📘 **[QUICKSTART.md](./QUICKSTART.md)** - Quick reference for deployment and usage
- 📗 **[DEPLOYMENT.md](./DEPLOYMENT.md)** - Comprehensive deployment guide
- 📝 **[DEPLOYMENT_CHECKLIST.md](./DEPLOYMENT_CHECKLIST.md)** - Validation checklist
- 🤝 **[SHARING.md](./SHARING.md)** - Guide for sharing this repository

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For issues, questions, or contributions, please:
- Check the [documentation](#documentation)
- Review [DEPLOYMENT_CHECKLIST.md](./DEPLOYMENT_CHECKLIST.md)
- Submit an issue on GitHub

---

**Ready to deploy?** Check out the [QUICKSTART.md](./QUICKSTART.md) guide!