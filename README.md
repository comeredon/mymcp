# MCP Azure PDF Knowledge Server

A production-ready MCP (Model Context Protocol) server that provides semantic search and document retrieval over indexed PDF documents. Built with TypeScript/Express, deployed on Azure Container Apps behind API Management, and fully integrated with GitHub Copilot.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Azure (Sweden Central)                           │
│                                                                          │
│  ┌────────────────────┐                                                 │
│  │  GitHub Copilot /  │                                                 │
│  │  MCP Client        │                                                 │
│  └─────────┬──────────┘                                                 │
│            │ HTTPS + Ocp-Apim-Subscription-Key                          │
│            │                                                            │
│  ┌─────────▼──────────────────────────────────────────────────┐        │
│  │      Azure API Management (Consumption tier)                │        │
│  │  ┌──────────────────────────────────────────────────┐      │        │
│  │  │  MCP API (4 operations):                         │      │        │
│  │  │  • GET  /mcp/health       (no auth)             │      │        │
│  │  │  • POST /mcp/api/tools    (MCP JSON-RPC)        │      │        │
│  │  │  • POST /mcp/api/search   (REST)                │      │        │
│  │  │  • POST /mcp/api/fetch    (REST)                │      │        │
│  │  └──────────────────────────────────────────────────┘      │        │
│  │  Policy: injects x-api-key header → backend               │        │
│  │  Rate limit: 100 calls / 60 seconds                        │        │
│  └──────────────────────┬───────────────────────────────────────┘        │
│                         │                                               │
│  ┌──────────────────────▼────────────────────────────────────┐          │
│  │      Container Apps Environment                           │          │
│  │  ┌────────────────────────────────────────────────┐       │          │
│  │  │   MCP Server (Container App)                   │       │          │
│  │  │   • Node.js 22 + TypeScript + Express          │       │          │
│  │  │   • Helmet, CORS, rate limiting                │       │          │
│  │  │   • API key auth (timing-safe, fail-closed)    │       │          │
│  │  │   • User-assigned Managed Identity             │       │          │
│  │  └────────┬───────────────┬───────────┬────────────┘       │          │
│  └───────────┼───────────────┼───────────┼─────────────────────┘          │
│              │               │           │                               │
│     Managed Identity    Managed Identity │                               │
│              │               │           │                               │
│  ┌───────────▼──────┐ ┌─────▼────────┐ ┌▼──────────────────┐           │
│  │ Azure AI Search   │ │ Storage Acct │ │ Azure OpenAI      │           │
│  │ (AAD-only auth)   │ │ (no shared   │ │ (AAD-only auth)   │           │
│  │                   │ │  key access) │ │                   │           │
│  │ Index: pdf-index  │ │ Containers:  │ │ Deployments:      │           │
│  │ • Semantic search │ │ • pdfs       │ │ • text-embedding  │           │
│  │ • Vector search   │ │ • documents  │ │   -3-large        │           │
│  │ • Hybrid ranking  │ │ • pdf-images │ │ • gpt-4o          │           │
│  └──────────┬────────┘ └──────────────┘ └───────────────────┘           │
│             │                                                            │
│  ┌──────────▼────────┐  ┌──────────────┐  ┌──────────────────┐         │
│  │ AI Foundry Svcs   │  │ Container    │  │ Log Analytics    │         │
│  │ (skillset billing │  │ Registry     │  │ (centralized     │         │
│  │  via Managed ID)  │  │ (ACR Pull    │  │  logging)        │         │
│  └───────────────────┘  │  via MI)     │  └──────────────────┘         │
│                          └──────────────┘                                │
└─────────────────────────────────────────────────────────────────────────┘
```

## Security

All services enforce **AAD-only authentication** — API keys and shared access keys are disabled across the board.

| Layer | Controls |
|-------|----------|
| **API Management** | Subscription key required, x-api-key injected via policy, rate limiting (100/60s), CORS |
| **Container App** | API key middleware (timing-safe comparison, fail-closed), Helmet security headers, 1 MB request limit |
| **Data services** | `disableLocalAuth: true` on Search and OpenAI, `allowSharedKeyAccess: false` on Storage |
| **Identity** | User-assigned Managed Identity for the app, system-assigned MI for Search indexer pipeline |
| **RBAC** | 10 least-privilege role assignments (Search Index Data Contributor/Reader, Storage Blob Data Contributor/Reader, Cognitive Services OpenAI User, Cognitive Services User, ACR Pull, Search Service Contributor) |

## Features

- **Semantic + Vector Hybrid Search** — Queries use Azure AI Search with semantic ranking and text-embedding-3-large vectors (kNN with floor of 50 for recall)
- **Document Retrieval** — Fetch full document text or filter by specific page numbers
- **MCP JSON-RPC Protocol** — Full MCP handshake (`initialize`, `tools/list`, `tools/call`) for GitHub Copilot integration
- **Integrated Vectorization Pipeline** — Automated PDF ingestion using Document Layout skill, GPT-4o summarization, and OpenAI embeddings
- **Infrastructure as Code** — Complete Bicep modules with parameterized deployment via Azure Developer CLI (`azd`)
- **Auto-scaling** — Container App scales 1–10 replicas based on HTTP traffic

## Quick Start

### Prerequisites

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (`az --version`)
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) (`azd version`)
- [Node.js 22+](https://nodejs.org/) (`node --version`)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (running)
- Azure subscription with Contributor access

### 1. Deploy Infrastructure

```powershell
# Login
az login
azd auth login

# Initialize and deploy (provisions all Azure resources + builds and deploys container)
azd up
```

`azd up` will prompt for environment name, subscription, and location, then provision all resources via Bicep and deploy the container image.

The deployment creates:

| Resource | Purpose |
|----------|---------|
| API Management (Consumption) | Public gateway with subscription key auth |
| Container App | Runs the MCP server (Node.js 22 + Express) |
| Container Apps Environment | Hosting environment for the container |
| Container Registry | Stores Docker images |
| Azure AI Search (Basic) | Semantic + vector search index |
| Azure OpenAI | text-embedding-3-large + gpt-4o deployments |
| Azure AI Services | Multi-service resource for skillset billing (keyless) |
| Storage Account | Blob containers for PDFs, documents, and images |
| Log Analytics | Centralized application and infrastructure logging |
| User-assigned Managed Identity | Service-to-service auth (10 RBAC roles) |
| Virtual Network (optional) | Private networking (`deployVNet = true`) |

### 2. Upload PDFs and Create the Search Pipeline

```powershell
# Upload PDF files to the 'pdfs' blob container
az storage blob upload --account-name <storage-account> --container-name pdfs `
  --file ./my-document.pdf --name my-document.pdf --auth-mode login

# Deploy the integrated vectorization pipeline (data source, index, skillset, indexer)
./setup-search-pipeline.ps1
```

The pipeline script (`setup-search-pipeline.ps1`) uses API version `2025-11-01-preview` and creates:
- **Data source** — connects to the `pdfs` blob container via Managed Identity
- **Index** — `pdf-index` with text, vector (3072-dim), and metadata fields + semantic configuration
- **Skillset** — Document Layout skill → GPT-4o ChatCompletion summarization → OpenAI embedding, with AI Services keyless billing
- **Indexer** — runs the pipeline, chunking PDFs into searchable text + vector embeddings

### 3. Test Your Deployment

```powershell
# Get the APIM gateway URL
$apimUrl = azd env get-value APIM_GATEWAY_URL

# Health check (no auth required)
Invoke-RestMethod "$apimUrl/mcp/health"

# List available MCP tools
$body = @{ jsonrpc="2.0"; id=1; method="tools/list" } | ConvertTo-Json
Invoke-RestMethod -Method POST "$apimUrl/mcp/api/tools" `
  -Headers @{ "Content-Type"="application/json"; "Ocp-Apim-Subscription-Key"="<your-key>" } `
  -Body $body

# Search your indexed PDFs
$body = @{
  jsonrpc = "2.0"; id = 2; method = "tools/call"
  params = @{ name = "search"; arguments = @{ query = "installation guide"; top = 5 } }
} | ConvertTo-Json -Depth 5
Invoke-RestMethod -Method POST "$apimUrl/mcp/api/tools" `
  -Headers @{ "Content-Type"="application/json"; "Ocp-Apim-Subscription-Key"="<your-key>" } `
  -Body $body
```

### 4. Configure GitHub Copilot

Add the MCP server to your VS Code settings or workspace `mcp.json`:

```json
{
  "mcpServers": {
    "pdf-search-mcp": {
      "type": "http",
      "url": "https://<your-apim>.azure-api.net/mcp/api/tools",
      "headers": {
        "Content-Type": "application/json",
        "Ocp-Apim-Subscription-Key": "<your-subscription-key>"
      }
    }
  }
}
```

Then use it in GitHub Copilot Chat — Copilot will automatically discover the `search` and `fetch` tools:

```
Search my PDFs for "configuration options"
What does the documentation say about installation?
Fetch the full content of document XYZ
```

## API Reference

All endpoints are served through APIM at `https://<apim-name>.azure-api.net/mcp`.

### `GET /mcp/health`

Health check. No authentication required.

```json
{ "status": "healthy", "timestamp": "2025-02-26T...", "service": "mcp-azure-pdf" }
```

### `POST /mcp/api/tools` (MCP JSON-RPC)

The primary endpoint for MCP clients (including GitHub Copilot). Supports the full MCP protocol:

| Method | Description |
|--------|-------------|
| `initialize` | MCP handshake — returns server capabilities |
| `tools/list` | Returns available tools (`search`, `fetch`) |
| `tools/call` | Executes a tool with the given arguments |

**Search** via `tools/call`:
```json
{
  "jsonrpc": "2.0", "id": 1, "method": "tools/call",
  "params": {
    "name": "search",
    "arguments": { "query": "your search query", "top": 5 }
  }
}
```

**Fetch** via `tools/call`:
```json
{
  "jsonrpc": "2.0", "id": 2, "method": "tools/call",
  "params": {
    "name": "fetch",
    "arguments": { "id": "document-id", "pages": [1, 2, 3] }
  }
}
```

### `POST /mcp/api/search` (REST)

Direct search endpoint (non-MCP clients).

```json
{ "query": "your search query", "top": 5 }
```

### `POST /mcp/api/fetch` (REST)

Direct document retrieval endpoint.

```json
{ "id": "document-id", "pages": [1, 2, 3] }
```

## Configuration

### Deployment Parameters (`infra/main.bicep`)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `environmentName` | — | Unique environment name (generates resource token) |
| `location` | `swedencentral` | Azure region |
| `searchIndexName` | `pdf-index` | Search index name |
| `searchServiceSku` | `basic` | AI Search tier |
| `serverApiKey` | Auto-generated | API key for the MCP server |
| `containerAppConfig` | 0.25 CPU / 0.5Gi / 1–10 replicas | Container sizing |
| `openAiConfig` | text-embedding-3-large + gpt-4o | Model deployments |
| `deployApim` | `true` | Deploy API Management gateway |
| `deployVNet` | `false` | Deploy VNet for private networking |
| `blobContainers` | pdfs, documents, pdf-images | Storage containers |

### Local Development

```powershell
# Copy and fill in environment variables
cp .env.example .env.local

# Build and run locally
npm run dev-local
```

### Build Commands

```bash
npm run build        # Compile TypeScript
npm start            # Run compiled server
npm run dev          # Build and run
npm run dev-local    # Run with local .env.local
npm run clean        # Remove dist/
```

## Project Structure

```
├── src/
│   └── server.ts                     # MCP server (Express, MCP JSON-RPC, search, fetch)
├── infra/                            # Infrastructure as Code (Bicep)
│   ├── main.bicep                    # Main orchestrator (12 modules, 10 role assignments)
│   ├── abbreviations.json            # Resource naming conventions
│   └── core/
│       ├── ai/cognitiveservices.bicep       # OpenAI + AI Services
│       ├── gateway/apim.bicep               # API Management + MCP API
│       ├── host/container-app.bicep         # Container App
│       ├── host/container-apps-environment.bicep
│       ├── host/container-registry.bicep    # ACR
│       ├── monitor/loganalytics.bicep       # Log Analytics
│       ├── network/vnet.bicep               # VNet (optional)
│       ├── search/search-services.bicep     # Azure AI Search
│       ├── security/managed-identity.bicep  # User-assigned MI
│       ├── security/role.bicep              # RBAC assignments
│       └── storage/storage-account.bicep    # Blob storage
├── .github/
│   ├── copilot-instructions.md       # Copilot repo-level context
│   ├── agents/                       # Custom Copilot agents (6)
│   ├── skills/                       # Reusable agent skills (6 categories)
│   └── workflows/                    # GitHub Actions (security review)
├── azure.yaml                        # Azure Developer CLI service config
├── Dockerfile                        # Node.js 22 Alpine, non-root user, health check
├── setup-search-pipeline.ps1         # Deploys data source, index, skillset, indexer
├── setup-search-pipeline.http        # REST Client file for pipeline testing
├── mcp.json                          # MCP client config template
├── deploy.ps1                        # PowerShell deployment script
├── validate-deployment.ps1           # Post-deployment validation
├── dev-local.ps1                     # Local development launcher
└── .env.example                      # Environment variables template
```

## Copilot Agents & Skills

This repository includes 6 custom GitHub Copilot agents and 17 reusable skills in `.github/agents/` and `.github/skills/`. These are designed for PL/I-to-Java translation workflows but can be adapted for other tasks.

Invoke an agent in Copilot Chat with `@AgentName`:

```
@ProgramManager   — Analyze source code and create translation specs
@DeveloperAgent   — Implement Java 21 code from specifications
@TesterAgent      — Create and run JUnit 5 tests
@SecurityAgent    — Scan code for vulnerabilities (OWASP)
@DevOpsAgent      — CI/CD pipelines and Docker builds
@DiagramAgent     — Generate C4 architecture diagrams
```

A GitHub Actions workflow (`security-review-java`) automatically triggers a security scan when Java code is pushed.

## Monitoring

```powershell
# View application logs
azd logs
# or
az containerapp logs show --name <app-name> --resource-group <rg-name> --tail 50

# Validate deployment health
.\validate-deployment.ps1 -ResourceGroupName <your-rg-name>
```

## Documentation

- [QUICKSTART.md](./QUICKSTART.md) — Quick deployment reference
- [DEPLOYMENT.md](./DEPLOYMENT.md) — Detailed deployment guide
- [DEPLOYMENT_CHECKLIST.md](./DEPLOYMENT_CHECKLIST.md) — Post-deployment validation checklist
- [SECURITY.md](./SECURITY.md) — Security policy
- [SHARING.md](./SHARING.md) — Guide for sharing this repository

## Contributing

- **Fork freely** — adapt the code to your needs
- **Pull requests welcome** — fork → feature branch → PR with description
- **Protected main branch** — all changes require PR review and approval
- **Submit issues** — report bugs or suggest enhancements via GitHub Issues

## License

MIT — see [LICENSE](./LICENSE) for details.