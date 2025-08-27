# 🔍 Finding Your Azure AI Search Environment Variables

This guide helps you find the actual values for your `.env.local` file.

## 1. 🔍 SEARCH_ENDPOINT and SEARCH_KEY

### Option A: Using Azure Portal
1. Go to [Azure Portal](https://portal.azure.com)
2. Search for "AI Search" or "Search services"
3. Click on your search service
4. **SEARCH_ENDPOINT**: Copy the URL from the "Overview" page (e.g., `https://yoursearch.search.windows.net/`)
5. **SEARCH_KEY**: Go to "Keys" in the left menu → Copy one of the "Admin keys"

### Option B: Using Azure CLI
```powershell
# List all search services
az search service list --output table

# Get specific search service details (replace 'your-service-name')
az search service show --name "your-service-name" --resource-group "your-rg" --query "hostName" -o tsv

# Get admin keys (replace 'your-service-name' and 'your-rg')
az search admin-key show --service-name "your-service-name" --resource-group "your-rg"
```

## 2. 📄 SEARCH_INDEX

This is the name of your search index that contains your PDF documents.

### Option A: Using Azure Portal
1. In your Search service → Go to "Indexes" 
2. Copy the name of your PDF index

### Option B: Using Azure CLI
```powershell
# List indexes in your search service
az search index list --service-name "your-service-name" --resource-group "your-rg" --output table
```

**Common index names:**
- `pdf-index`
- `documents`
- `pdf-documents` 
- `knowledge-base`

## 3. 🔐 SERVER_API_KEY

This is YOUR custom API key for securing your MCP server. You can create any secure string.

### Generate a Secure API Key

**Option A: PowerShell (Recommended)**
```powershell
# Generate a random 32-character API key
-join (1..32 | ForEach {[char]((65..90) + (97..122) + (48..57) | Get-Random)})
```

**Option B: Online Generator**
- Go to [passwordsgenerator.net](https://passwordsgenerator.net/)
- Generate a 32+ character alphanumeric key
- Use this as your `SERVER_API_KEY`

**Option C: Manual Creation**
Create something like: `myPdfSearchAPI2025SecureKey789`

## 4. ✅ Example Complete Configuration

After finding your values, your `.env.local` should look like:

```bash
# Real example values (yours will be different)
SEARCH_ENDPOINT=https://mycompany-search.search.windows.net/
SEARCH_KEY=1A2B3C4D5E6F7G8H9I0J1K2L3M4N5O6P
SEARCH_INDEX=pdf-documents
SERVER_API_KEY=mySecureAPIKey2025ForPDFSearch
PORT=8080
AZURE_RESOURCE_GROUP=mcpserver
AZURE_LOCATION=swedencentral
```

## 5. 🧪 Quick Commands to Run

Run these commands to quickly find your values:

```powershell
# 1. Find your search services
az search service list --query "[].{Name:name, ResourceGroup:resourceGroup, Location:location}" --output table

# 2. If you have a search service, get its endpoint (replace SERVICE_NAME and RG_NAME)
az search service show --name "SERVICE_NAME" --resource-group "RG_NAME" --query "hostName" -o tsv

# 3. Get the admin key (replace SERVICE_NAME and RG_NAME)
az search admin-key show --service-name "SERVICE_NAME" --resource-group "RG_NAME" --query "primaryKey" -o tsv

# 4. List indexes (replace SERVICE_NAME and RG_NAME)
az search index list --service-name "SERVICE_NAME" --resource-group "RG_NAME" --query "[].name" -o tsv

# 5. Generate API key
-join (1..32 | ForEach {[char]((65..90) + (97..122) + (48..57) | Get-Random)})
```

## 6. 🔍 Don't Have Azure AI Search Yet?

If you don't have an Azure AI Search service with PDF documents, you'll need to:

1. **Create AI Search Service**:
   ```powershell
   az search service create --name "my-pdf-search" --resource-group "mcpserver" --sku "basic" --location "swedencentral"
   ```

2. **Index Your PDF Documents**: Use Azure AI Document Intelligence or custom indexing to upload and index your PDF files.

3. **Create Search Index**: Set up an index with fields like `id`, `content`, `title`, `source_url`, etc.

## 7. ✅ Validation

After updating your `.env.local`, validate it:

```powershell
./validate-env.ps1
```

This will check that all your values are properly formatted and ready for deployment!

---

**Need Help?** 
- Check if you have existing AI Search services: `az search service list`
- Ensure you're logged into the right Azure subscription: `az account show`
- If you need to create everything from scratch, consider using the deployment script which can create the search service for you.