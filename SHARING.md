# Sharing and Reusability Guide

This guide explains how to share this MCP server deployment with others so they can deploy it in their own Azure environment.

## 🎯 Design Principles

This deployment is designed to be **fully reusable** and **environment-agnostic**:

✅ **No hardcoded values** - All resources use parameters and generated unique names
✅ **Parameterized configuration** - Users can customize deployment via parameters
✅ **Managed Identity** - No hardcoded credentials or secrets
✅ **Infrastructure as Code** - All resources defined in Bicep templates
✅ **Self-contained** - Single command deployment with `azd up` or `./deploy.ps1`

## 📦 What to Share

Share these files with others:

### Required Files
```
├── infra/                      # Infrastructure as Code
│   ├── main.bicep             # Main deployment template
│   ├── abbreviations.json     # Resource naming
│   └── core/                  # Reusable modules
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
├── src/                       # Application code
│   └── server.ts
├── azure.yaml                 # Azure Developer CLI config
├── deploy.ps1                 # Deployment script
├── Dockerfile                 # Container definition
├── package.json               # Dependencies
├── tsconfig.json              # TypeScript config
├── README.md                  # Documentation
├── DEPLOYMENT.md              # Deployment guide
└── DEPLOYMENT_CHECKLIST.md    # Validation checklist
```

### DO NOT Share
```
.env                           # Local environment variables
.env.local                     # Local secrets
.azure/                        # User-specific azd state
dist/                          # Build artifacts
node_modules/                  # Dependencies
```

## 🚀 Deployment Options for Recipients

Users can deploy using either method:

### Option 1: Azure Developer CLI (Recommended)
```bash
# 1. Login to Azure
az login

# 2. Initialize environment
azd env new <environment-name>

# 3. Deploy everything
azd up
```

### Option 2: PowerShell Script
```powershell
# 1. Login to Azure
az login

# 2. Deploy with defaults
./deploy.ps1

# 3. Or customize
./deploy.ps1 `
  -ResourceGroupName "my-rg" `
  -Location "eastus" `
  -EnvironmentName "prod"
```

## 🔧 Customization Parameters

Recipients can customize these parameters:

### Basic Parameters
| Parameter | Description | Default |
|-----------|-------------|---------|
| `EnvironmentName` | Environment identifier | `mcp` |
| `ResourceGroupName` | Resource group name | `mcp-server-rg` |
| `Location` | Azure region | `swedencentral` |
| `SearchIndexName` | Search index name | `pdf-index` |
| `ApiKey` | Custom API key | Auto-generated |

### Optional Features
| Parameter | Description | Default |
|-----------|-------------|---------|
| `DeployApim` | Deploy API Management | `false` |
| `ApimPublisherEmail` | APIM publisher email | `admin@contoso.com` |
| `ApimPublisherName` | APIM publisher name | `Contoso` |
| `DeployVNet` | Deploy Virtual Network | `false` |

### Advanced Configuration
Edit `infra/main.bicep` for:
- Container app resources (CPU/Memory)
- OpenAI model deployments
- Search service SKU
- Storage account settings
- Network configuration

## 🌍 Multi-Environment Deployment

Users can deploy to multiple environments:

```powershell
# Development
./deploy.ps1 -EnvironmentName "dev" -ResourceGroupName "mcp-dev-rg"

# Staging
./deploy.ps1 -EnvironmentName "staging" -ResourceGroupName "mcp-staging-rg"

# Production
./deploy.ps1 -EnvironmentName "prod" -ResourceGroupName "mcp-prod-rg" -Location "eastus"
```

Each deployment is isolated with unique resource names.

## 🔐 Security Considerations

This deployment follows security best practices:

1. **Managed Identity** - No credentials in code or environment variables
2. **RBAC** - Least privilege access with role assignments
3. **Secrets Management** - All secrets stored in Container App secrets
4. **TLS** - HTTPS enforced for all endpoints
5. **Key Rotation** - Easy to rotate API keys via parameters

Recipients should:
- Review RBAC permissions before deployment
- Configure network restrictions if needed
- Set up monitoring and alerts
- Implement backup procedures

## 📋 Deployment Checklist for Recipients

Before deploying, recipients should:

1. **Prerequisites**
   - [ ] Azure subscription with Contributor access
   - [ ] Azure CLI installed and logged in
   - [ ] Docker Desktop running
   - [ ] Node.js 20+ installed

2. **Configuration**
   - [ ] Review `infra/main.bicep` parameters
   - [ ] Choose appropriate Azure region
   - [ ] Decide on resource naming convention
   - [ ] Configure optional features (APIM, VNet)

3. **Post-Deployment**
   - [ ] Upload PDF documents to storage
   - [ ] Create and populate search index
   - [ ] Test endpoints and connectivity
   - [ ] Configure monitoring and alerts
   - [ ] Document connection details

## 🧪 Testing the Deployment

Recipients should verify deployment:

```powershell
# 1. Check health
curl https://<your-app-url>/health

# 2. Test search
curl -X POST https://<your-app-url>/api/search `
  -H "x-api-key: <your-api-key>" `
  -H "Content-Type: application/json" `
  -d '{"query": "test", "top": 5}'

# 3. View logs
az containerapp logs show --name <app-name> --resource-group <rg-name>
```

## 📚 Documentation to Share

Include these documents:
- `README.md` - Overview and features
- `DEPLOYMENT.md` - Detailed deployment guide
- `DEPLOYMENT_CHECKLIST.md` - Validation checklist
- `SHARING.md` - This file

## 💡 Tips for Recipients

1. **Start Simple** - Deploy with defaults first, customize later
2. **One Region** - Deploy to a single region initially
3. **Test Thoroughly** - Use the deployment checklist
4. **Monitor Costs** - Set up cost alerts in Azure Portal
5. **Read Docs** - Review all documentation before deploying

## 🆘 Support

Recipients can:
- Review deployment logs for errors
- Check Azure Portal for resource status
- Use deployment checklist for troubleshooting
- Consult Azure documentation for service-specific issues

## 📝 Customization Examples

### Change OpenAI Models
Edit `infra/main.bicep`:
```bicep
param openAiConfig object = {
  deployEmbeddings: true
  embeddingsModel: 'text-embedding-3-large'  // Modern, 3072 dimensions
  embeddingsModelVersion: '1'
  deployGpt: true
  gptModel: 'gpt-4o'  // With vision support for images/charts
  gptModelVersion: '2024-08-06'  // Latest version
  gptModelVersion: '2024-07-18'
}
```

### Change Container Resources
Edit `infra/main.bicep`:
```bicep
param containerAppConfig object = {
  cpu: '0.5'        // Increased
  memory: '1Gi'     // Increased
  minReplicas: 2    // Changed
  maxReplicas: 20   // Changed
}
```

### Enable Private Networking
```powershell
./deploy.ps1 -DeployVNet
```

Then configure private endpoints in the Bicep templates.

## ✅ Validation

After deployment, recipients should have:
- ✅ All resources deployed successfully
- ✅ No hardcoded environment-specific values
- ✅ Working health and API endpoints
- ✅ Proper RBAC permissions
- ✅ Monitoring and logging enabled

## 🎉 Ready to Share!

This deployment is designed to be shared and deployed by anyone with:
- An Azure subscription
- Basic Azure CLI knowledge
- Access to the required files

No additional setup or configuration required!
