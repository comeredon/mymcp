# Environment Variables Setup Guide

This guide shows you how to configure environment variables locally and automatically deploy them to Azure Container Apps.

## 🔧 Quick Setup

### 1. Create Your Environment File

```powershell
# Copy the example file
copy .env.example .env.local
```

### 2. Edit Your Environment Variables

Open `.env.local` and fill in your actual values:

```bash
# Azure AI Search Configuration
SEARCH_ENDPOINT=https://your-search-service.search.windows.net/
SEARCH_KEY=your-actual-search-admin-key
SEARCH_INDEX=your-pdf-index-name

# Server Configuration  
SERVER_API_KEY=your-secure-api-key
PORT=8080

# Azure Deployment Settings (optional)
AZURE_RESOURCE_GROUP=mcpserver
AZURE_LOCATION=swedencentral
```

### 3. Deploy to Azure

```powershell
# Deploy with your environment variables
./deploy-with-env.ps1

# Or test first with dry run
./deploy-with-env.ps1 -DryRun
```

## 📁 File Structure

```
├── .env.example          # Template with all variables
├── .env.local            # Your actual values (git-ignored)
├── deploy-with-env.ps1   # Deployment script that reads .env.local
├── dev-local.ps1         # Local development script
└── .gitignore            # Ensures .env.local is never committed
```

## 🔒 Security Features

✅ **Local Environment Files are Git-Ignored**: Your `.env.local` file is never committed  
✅ **Automatic Secret Management**: Sensitive values are stored as Container App secrets  
✅ **No Hardcoded Values**: All configuration comes from your environment file  
✅ **Validation**: Script validates all required variables before deployment  

## 🚀 Usage Examples

### Local Development
```powershell
# Run locally with your environment variables
npm run dev-local

# Or manually
./dev-local.ps1
```

### Azure Deployment
```powershell
# Standard deployment
./deploy-with-env.ps1

# Deploy to different resource group
./deploy-with-env.ps1 -ResourceGroup "my-other-rg" -Location "eastus"

# Test what would be deployed (no actual deployment)
./deploy-with-env.ps1 -DryRun

# Use different environment file
./deploy-with-env.ps1 -EnvFile ".env.production"
```

## 📋 Environment Variables Reference

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `SEARCH_ENDPOINT` | Azure AI Search service URL | `https://mysearch.search.windows.net/` |
| `SEARCH_KEY` | Azure AI Search admin key | `1234567890ABCDEF...` |
| `SEARCH_INDEX` | Name of your PDF search index | `pdf-documents` |
| `SERVER_API_KEY` | API key for client authentication | `my-secure-api-key-123` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | Server port | `8080` |
| `AZURE_RESOURCE_GROUP` | Target resource group | `mcpserver` |
| `AZURE_LOCATION` | Azure region | `swedencentral` |

### Development Variables

| Variable | Description | Use Case |
|----------|-------------|----------|
| `NODE_ENV` | Environment mode | Set to `development` for local testing |

## 🔄 How Environment Variables Flow

### Local Development:
1. `dev-local.ps1` reads `.env.local`
2. Sets process environment variables
3. Starts Node.js server with those variables

### Azure Deployment:
1. `deploy-with-env.ps1` reads `.env.local`
2. Validates required variables
3. Deploys infrastructure to Azure
4. Configures Container App secrets for sensitive values
5. Sets environment variables in Container App
6. Your application runs with those variables in Azure

## 🛠️ Advanced Configuration

### Multiple Environments

Create different environment files:
```
.env.local          # Local development
.env.staging        # Staging environment  
.env.production     # Production environment
```

Deploy to different environments:
```powershell
./deploy-with-env.ps1 -EnvFile ".env.staging" -ResourceGroup "mcpserver-staging"
./deploy-with-env.ps1 -EnvFile ".env.production" -ResourceGroup "mcpserver-prod"
```

### Custom API Keys

Generate secure API keys:
```powershell
# Generate a random API key
[System.Web.Security.Membership]::GeneratePassword(32, 5)
```

### Updating Environment Variables

To update variables after deployment:
```powershell
# 1. Update your .env.local file
# 2. Re-run deployment (only Container App will be updated)
./deploy-with-env.ps1
```

## 🧪 Testing Your Configuration

### Validate Environment File
```powershell
# Dry run to check your variables
./deploy-with-env.ps1 -DryRun
```

### Test Local Server
```powershell
# Start with your environment
npm run dev-local

# Test health endpoint
curl http://localhost:8080/health

# Test search (replace YOUR_API_KEY with your SERVER_API_KEY)
curl -X POST http://localhost:8080/api/search -H "x-api-key: YOUR_API_KEY" -H "Content-Type: application/json" -d '{"query": "test", "top": 3}'
```

### Test Azure Deployment
```powershell
# After deployment, test the Azure endpoint
curl https://your-container-app-url.azurecontainerapps.io/health
```

## ⚠️ Important Notes

1. **Never commit `.env.local`** - It contains sensitive information
2. **Use strong API keys** - Your `SERVER_API_KEY` protects your search API
3. **Keep `.env.example` updated** - When you add new variables, update the example
4. **Test locally first** - Use `npm run dev-local` before deploying
5. **Use dry run** - Test deployments with `-DryRun` flag first

## 🆘 Troubleshooting

### Environment File Not Found
```
Error: Environment file '.env.local' not found!
Solution: Copy .env.example to .env.local and fill in values
```

### Missing Required Variables
```
Error: Missing required environment variables: SEARCH_KEY
Solution: Add the missing variable to your .env.local file
```

### Azure Authentication Issues
```
Error: Please login to Azure CLI first: az login
Solution: Run 'az login' and authenticate
```

### Invalid Search Endpoint
```
Error: Search service connection failed
Solution: Verify SEARCH_ENDPOINT and SEARCH_KEY are correct
```

Your environment variables are now fully managed locally and automatically deployed to Azure! 🎉