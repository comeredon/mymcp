# Azure Portal Guide: Finding Environment Variables

## Step 1: Find Your Search Service (SEARCH_ENDPOINT & SEARCH_KEY)

1. **Go to Azure Portal**: https://portal.azure.com
2. **Navigate to your resource group**:
   - Click "Resource groups" in the left menu
   - Find and click on your resource group: **mcpserver**
3. **Find your Search service**:
   - Look for a resource with type "Search service" or "Azure AI Search"
   - Click on it

### Get SEARCH_ENDPOINT:
- In the Search service overview page, look for **"Url"** or **"Search service URL"**
- It will look like: `https://your-search-service.search.windows.net`
- Copy this entire URL (including https://)

### Get SEARCH_KEY:
- In your Search service, click **"Keys"** in the left menu
- Copy either the **"Primary admin key"** or **"Secondary admin key"**
- This is a long string like: `1234567890ABCDEF1234567890ABCDEF`

## Step 2: Find Your Search Index (SEARCH_INDEX)

1. **In your Search service**, click **"Indexes"** in the left menu
2. **Look for your PDF index**:
   - You should see one or more indexes listed
   - Look for the one that contains your PDF content
   - Common names might be: `pdf-index`, `documents`, `content`, etc.
3. **Copy the exact index name** (case-sensitive)

## Step 3: Generate SERVER_API_KEY

This is a custom API key you create for your MCP server. You can generate a secure random key:

### Option 1: Use PowerShell (Recommended)
```powershell
# Run this in PowerShell to generate a secure random key
[System.Web.Security.Membership]::GeneratePassword(32, 5)
```

### Option 2: Use online generator
- Go to: https://generate-secret.vercel.app/32
- Copy the generated key

### Option 3: Manual creation
- Create a strong password with at least 20 characters
- Mix of letters, numbers, and symbols
- Example format: `MySecureKey123!@#$%^&*()_+`

## Step 4: Update Your .env.local File

Once you have all values, update your `.env.local` file:

```env
SEARCH_ENDPOINT=https://your-search-service.search.windows.net
SEARCH_KEY=your-admin-key-here
SEARCH_INDEX=your-index-name
SERVER_API_KEY=your-generated-api-key
```

## Step 5: Validate Your Configuration

Run the validation script:
```powershell
./validate-env.ps1
```

## Troubleshooting

### Can't find Search service?
- Make sure you're in the correct subscription
- Check if the Search service is in a different resource group
- Search for "AI Search" or "Search" in the portal search bar

### Can't find indexes?
- Your Search service might not have any indexes yet
- You may need to create and populate an index first
- Check the "Import data" wizard in your Search service

### Keys not working?
- Make sure you copied the full key without extra spaces
- Try both primary and secondary admin keys
- Ensure you have the right permissions on the Search service

## Next Steps

After updating `.env.local`:
1. Run `./validate-env.ps1` to verify your configuration
2. Run `./deploy-with-env.ps1` to deploy to Azure
3. Test your deployment with the health check endpoint