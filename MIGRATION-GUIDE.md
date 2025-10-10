# Migration Guide - Simplified Deployment

## What Changed?

We've significantly simplified the deployment process! The repository now has a unified deployment approach that requires **no pre-deployment setup**.

### Before (Old Approach)
- ❌ Required existing Azure AI Search service
- ❌ Required manual environment variable configuration
- ❌ Multiple deployment scripts (deploy.ps1, deploy-phases.ps1, deploy-with-env.ps1)
- ❌ Multiple Bicep templates (main.bicep, phase1-infra.bicep, phase2-app.bicep)
- ❌ Required validation script before deployment
- ❌ Extensive documentation spread across 6+ files

### After (New Approach)
- ✅ Creates all Azure resources automatically including Azure AI Search
- ✅ Single unified deployment script (deploy.ps1)
- ✅ Single Bicep template (main.bicep)
- ✅ No pre-deployment configuration needed
- ✅ Simplified documentation (README.md + DEPLOYMENT.md)
- ✅ Environment variables only needed for local development

## Breaking Changes

### Removed Files
The following files have been removed as they're no longer needed:

**Deployment Scripts:**
- `deploy-phases.ps1` - Replaced by unified deploy.ps1
- `deploy-with-env.ps1` - Replaced by unified deploy.ps1
- `validate-env.ps1` - No longer needed

**Infrastructure Templates:**
- `infra/phase1-infra.bicep` - Merged into main.bicep
- `infra/phase2-app.bicep` - Merged into main.bicep
- `infra/main.parameters.json` - Parameters now passed directly

**Documentation:**
- `ENV-SETUP.md` - Merged into README.md and DEPLOYMENT.md
- `ENV-SUMMARY.md` - No longer needed
- `FIND-VARIABLES.md` - No longer needed
- `AZURE-PORTAL-GUIDE.md` - No longer needed
- `CLEAN-REPO-SUMMARY.md` - No longer needed
- `SECURITY.md` - Basic security info moved to DEPLOYMENT.md

### Changed Files

**deploy.ps1** - Completely rewritten
- Now creates all resources including Azure AI Search
- Creates resource group if it doesn't exist
- Simplified parameter set
- Clear deployment output

**infra/main.bicep** - Significantly updated
- Now deploys Azure AI Search service (new resource)
- Auto-generates secure API keys
- Simplified parameters
- All resources in one template

**.env.example** - Simplified
- Clearer comments
- Focus on local development use
- Explains values come from deployment output

**README.md** - Streamlined
- Simplified Quick Start section
- Clear deployment instructions
- Updated GitHub Copilot integration guide

**DEPLOYMENT.md** - Rewritten
- Focus on new unified deployment
- Clear post-deployment steps
- Better troubleshooting section

## How to Use the New Deployment

### For New Users

Simply run:
```powershell
az login
./deploy.ps1
```

That's it! The script will create everything you need.

### For Existing Users

If you already have an Azure AI Search service with indexed PDFs:

**Option 1: Use the new deployment (Recommended)**
```powershell
# Deploy new infrastructure
./deploy.ps1 -ResourceGroupName "new-rg" -SearchIndexName "your-existing-index"

# Re-index your PDFs in the new search service
# Or point the app to your existing search service (requires manual configuration)
```

**Option 2: Continue with manual configuration**
You can still manually configure the container app environment variables to point to your existing search service using Azure Portal or Azure CLI.

## Benefits of the New Approach

1. **Faster Setup**: From hours to minutes
2. **Fewer Errors**: No manual configuration means fewer mistakes
3. **Better Security**: Auto-generated secure keys
4. **Easier Maintenance**: Single deployment script to understand
5. **Self-Contained**: Everything needed is in the repository

## Support

If you encounter issues with the new deployment:
1. Check DEPLOYMENT.md for detailed instructions
2. Verify Azure CLI is installed and you're logged in
3. Check Docker Desktop is running
4. Review deployment output for error messages

## Backward Compatibility

The deployed application remains fully compatible. The API endpoints, authentication, and functionality are unchanged. Only the deployment process has been simplified.
