# MCP Azure Deployment Validation Checklist

Use this checklist to ensure your deployment is complete and properly configured.

## ✅ Pre-Deployment Checklist

- [ ] Azure CLI installed and logged in (`az login`)
- [ ] Docker Desktop running
- [ ] Node.js 20+ installed
- [ ] Contributor access to Azure subscription
- [ ] Resource group permissions verified

## ✅ Infrastructure Deployment

### Core Resources
- [ ] Resource Group created
- [ ] Container Apps Environment deployed
- [ ] Container Registry deployed
- [ ] Log Analytics Workspace deployed
- [ ] Managed Identity created

### Data & AI Services
- [ ] Azure AI Search service deployed
- [ ] Storage Account created
- [ ] Blob containers (`pdfs`, `documents`) created
- [ ] Azure OpenAI account deployed
- [ ] OpenAI embeddings deployment created
- [ ] OpenAI chat deployment created

### Optional Components
- [ ] API Management deployed (default: enabled)
- [ ] APIM MCP API configured
- [ ] APIM backend connected to Container App
- [ ] APIM policies configured for authentication
- [ ] Virtual Network deployed (if enabled)

## ✅ RBAC Configuration

- [ ] Managed Identity has Search Index Data Contributor role
- [ ] Managed Identity has Storage Blob Data Contributor role
- [ ] Managed Identity has Cognitive Services OpenAI User role
- [ ] Managed Identity has ACR Pull role

## ✅ Application Deployment

- [ ] Docker image built successfully
- [ ] Docker image pushed to ACR
- [ ] Container App deployed
- [ ] Container App is running
- [ ] Health endpoint responding (`/health`)

## ✅ Configuration Verification

### Environment Variables
- [ ] `SEARCH_ENDPOINT` configured
- [ ] `SEARCH_KEY` configured (as secret)
- [ ] `SEARCH_INDEX` configured
- [ ] `STORAGE_CONNECTION_STRING` configured (as secret)
- [ ] `AZURE_STORAGE_ACCOUNT_NAME` configured
- [ ] `AZURE_STORAGE_CONTAINER_NAME` configured
- [ ] `AZURE_OPENAI_ENDPOINT` configured (as secret)
- [ ] `AZURE_OPENAI_KEY` configured (as secret)
- [ ] `AZURE_OPENAI_EMBEDDING_DEPLOYMENT` configured
- [ ] `AZURE_OPENAI_CHAT_DEPLOYMENT` configured
- [ ] `SERVER_API_KEY` configured (as secret)
- [ ] `PORT` configured

### Networking
- [ ] Container App ingress enabled
- [ ] **Container App external access: DISABLED (internal only)**
- [ ] **APIM Gateway: Public endpoint (production default)**
- [ ] APIM backend connected to Container App internal FQDN
- [ ] CORS configured (if needed)
- [ ] TLS/HTTPS enabled

## ✅ Data Setup

- [ ] PDF documents uploaded to blob storage
- [ ] Search index created
- [ ] Search index schema configured
- [ ] Documents indexed in AI Search
- [ ] Test search query returns results

## ✅ Testing

### Health & Connectivity
```bash
# Health check (via APIM Gateway)
curl https://your-apim-gateway-url/mcp/health

# Should return: {"status":"healthy"}

# Verify Container App is internal-only (should FAIL from external network)
curl https://your-container-app-url/health  # Expected: Connection refused or timeout
```

### API Functionality
```bash
# Test search endpoint (via APIM - no auth header needed)
curl -X POST https://your-apim-gateway-url/mcp/api/search \
  -H "Content-Type: application/json" \
  -d '{"query": "test", "top": 5}'
```

### MCP Tools Endpoint
```bash
# Test MCP tools endpoint (via APIM)
curl -X POST https://your-apim-gateway-url/mcp/api/tools \
  -H "Content-Type: application/json" \
  -d '{"tool": "search", "arguments": {"query": "test", "top": 5}}'
```

### Security Verification
```bash
# Verify Container App is NOT accessible externally
# This should fail with connection error
curl https://your-container-app-internal-url/health

# Verify APIM gateway is accessible
# This should succeed
curl https://your-apim-gateway-url/mcp/health
```

## ✅ Client Configuration

- [ ] `mcp.json` updated with APIM gateway URL (not Container App URL)
- [ ] No `x-api-key` header in client config (handled by APIM)
- [ ] GitHub Copilot can connect to server
- [ ] Search tool responds correctly
- [ ] Fetch tool responds correctly

## ✅ Security Review

- [ ] No hardcoded credentials in code
- [ ] Secrets stored in Container App secrets
- [ ] Managed Identity used where possible
- [ ] RBAC roles follow least privilege
- [ ] **Container App is internal-only (not exposed to internet)**
- [ ] **All external traffic routes through APIM gateway**
- [ ] **APIM policies inject API key automatically**
- [ ] TLS 1.2+ enforced

## ✅ Monitoring & Operations

- [ ] Log Analytics workspace connected
- [ ] Container App logs accessible
- [ ] Application Insights configured (optional)
- [ ] Alerts configured (optional)
- [ ] Auto-scaling configured

## ✅ Documentation

- [ ] Deployment outputs saved
- [ ] Connection details documented
- [ ] API key stored securely
- [ ] Runbook created for operations
- [ ] Disaster recovery plan documented

## 🔍 Verification Commands

```powershell
# Verify resource group
az group show --name <rg-name>

# List all resources
az resource list --resource-group <rg-name> --output table

# Check container app status
az containerapp show --name <app-name> --resource-group <rg-name> --query "properties.runningStatus"

# Verify Container App is internal-only
az containerapp show --name <app-name> --resource-group <rg-name> --query "properties.configuration.ingress.external"
# Should return: false

# Check APIM status
az apim show --name <apim-name> --resource-group <rg-name> --query "provisioningState"

# List APIM APIs
az apim api list --service-name <apim-name> --resource-group <rg-name> --output table

# View container logs
az containerapp logs show --name <app-name> --resource-group <rg-name> --tail 50

# Test storage access
az storage blob list --account-name <storage-name> --container-name pdfs

# Test search service
az search service show --name <search-name> --resource-group <rg-name>

# Test OpenAI deployment
az cognitiveservices account deployment list --name <openai-name> --resource-group <rg-name>
```

## 📊 Success Criteria

Your deployment is successful when:
- ✅ All resources are deployed and running
- ✅ APIM Gateway health endpoint returns 200 OK
- ✅ Container App is internal-only (external=false)
- ✅ Container App NOT accessible from internet
- ✅ Search returns relevant results via APIM
- ✅ No errors in application logs
- ✅ GitHub Copilot can use MCP tools via APIM
- ✅ Performance meets expectations

## 🐛 Troubleshooting

If any checklist item fails, refer to:
- [DEPLOYMENT.md](./DEPLOYMENT.md) - Detailed deployment guide
- [README.md](./README.md) - General documentation
- Azure Portal logs for specific error messages
- Container App logs: `az containerapp logs show`
