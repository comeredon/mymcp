#!/usr/bin/env bash
# MCP Azure PDF Server - Cleanup Script
# Removes all Azure resources created by deploy.sh

main() {
set -euo pipefail

# Default parameters
RESOURCE_GROUP_NAME="${RESOURCE_GROUP_NAME:-mcp-server-rg}"
PURGE_COGNITIVE="${PURGE_COGNITIVE:-false}"
PURGE_APIM="${PURGE_APIM:-false}"
PURGE_KEYVAULT="${PURGE_KEYVAULT:-false}"
PURGE_STORAGE="${PURGE_STORAGE:-false}"
CLEANUP_SEARCH_PIPELINE="${CLEANUP_SEARCH_PIPELINE:-false}"
SKIP_CONFIRM="${SKIP_CONFIRM:-false}"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --resource-group)     RESOURCE_GROUP_NAME="$2"; shift 2 ;;
        --purge-cognitive)    PURGE_COGNITIVE=true; shift ;;
        --purge-apim)         PURGE_APIM=true; shift ;;
        --purge-keyvault)     PURGE_KEYVAULT=true; shift ;;
        --purge-storage)      PURGE_STORAGE=true; shift ;;
        --cleanup-search)     CLEANUP_SEARCH_PIPELINE=true; shift ;;
        --purge-all)          PURGE_COGNITIVE=true; PURGE_APIM=true; PURGE_KEYVAULT=true; PURGE_STORAGE=true; CLEANUP_SEARCH_PIPELINE=true; shift ;;
        --yes)                SKIP_CONFIRM=true; shift ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --resource-group NAME   Resource group to delete (default: mcp-server-rg)"
            echo "  --purge-cognitive       Purge soft-deleted Azure AI Foundry resource (frees the name)"
            echo "  --purge-apim            Purge soft-deleted APIM instance (frees the name)"
            echo "  --purge-keyvault        Purge soft-deleted Key Vault instances (frees the name)"
            echo "  --purge-storage         Purge soft-deleted Storage Account instances (frees the name)"
            echo "  --cleanup-search        Clean up search pipeline components (indexer, skillset, index, datasource)"
            echo "  --purge-all             Purge all soft-deleted resources (cognitive + APIM + KeyVault + Storage)"
            echo "  --yes                   Skip confirmation prompt"
            echo "  -h, --help              Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                                  # Delete resource group (with confirmation)"
            echo "  $0 --yes                            # Delete without confirmation"
            echo "  $0 --purge-all --yes                # Delete and purge everything"
            echo "  $0 --resource-group my-rg --yes     # Delete a custom resource group"
            return 0
            ;;
        *) echo "Unknown option: $1"; return 1 ;;
    esac
done

echo "🧹 MCP Azure PDF Server - Cleanup"
echo "=================================="
echo ""

# Check Azure authentication
echo "Checking Azure authentication..."
if ! az account show --output none 2>/dev/null; then
    echo "❌ Not logged in to Azure. Run: az login"
    return 1
fi
logged_in_user=$(az account show --query "user.name" -o tsv)
subscription=$(az account show --query "name" -o tsv)
echo "✅ Logged in as: $logged_in_user"
echo "   Subscription: $subscription"
echo ""

# Check if resource group exists
if ! az group show --name "$RESOURCE_GROUP_NAME" --output none 2>/dev/null; then
    echo "⚠️  Resource group '$RESOURCE_GROUP_NAME' does not exist. Nothing to delete."
    if [[ "$PURGE_COGNITIVE" == "true" || "$PURGE_APIM" == "true" || "$PURGE_KEYVAULT" == "true" || "$PURGE_STORAGE" == "true" ]]; then
        echo ""
        echo "Checking for soft-deleted resources to purge..."
    else
        return 0
    fi
else
    # List resources in the group
    echo "📋 Resources in '$RESOURCE_GROUP_NAME':"
    az resource list --resource-group "$RESOURCE_GROUP_NAME" \
        --query "[].{Name:name, Type:type}" -o table
    echo ""

    # Capture resource names before deletion (for purge)
    cognitive_names=$(az resource list --resource-group "$RESOURCE_GROUP_NAME" \
        --resource-type "Microsoft.CognitiveServices/accounts" \
        --query "[].name" -o tsv 2>/dev/null || true)
    cognitive_location=$(az group show --name "$RESOURCE_GROUP_NAME" --query "location" -o tsv 2>/dev/null || true)

    apim_names=$(az resource list --resource-group "$RESOURCE_GROUP_NAME" \
        --resource-type "Microsoft.ApiManagement/service" \
        --query "[].name" -o tsv 2>/dev/null || true)

    # Confirmation
    if [[ "$SKIP_CONFIRM" != "true" ]]; then
        echo "⚠️  This will permanently delete resource group '$RESOURCE_GROUP_NAME' and ALL resources inside it."
        echo ""
        read -r -p "Are you sure? Type the resource group name to confirm: " confirm
        if [[ "$confirm" != "$RESOURCE_GROUP_NAME" ]]; then
            echo "❌ Confirmation failed. Aborting."
            return 1
        fi
    fi

    # Search pipeline cleanup (if requested)
    if [[ "$CLEANUP_SEARCH_PIPELINE" == "true" ]]; then
        echo ""
        echo "🔍 Cleaning up Azure Search pipeline components..."
        
        # Get search service name from resources
        search_service=$(az resource list --resource-group "$RESOURCE_GROUP_NAME" \
            --resource-type "Microsoft.Search/searchServices" \
            --query "[0].name" -o tsv 2>/dev/null || true)
            
        if [[ -n "$search_service" ]]; then
            echo "   Found search service: $search_service"
            
            # Get access token for search service  
            TOKEN=$(az account get-access-token --resource https://search.azure.com/ --query accessToken -o tsv 2>/dev/null || true)
            
            if [[ -n "$TOKEN" ]]; then
                echo "   Cleaning up pipeline components..."
                
                # Delete indexer
                echo "   - Deleting pdf-indexer..."
                curl -s -X DELETE "https://$search_service.search.windows.net/indexers/pdf-indexer?api-version=2025-11-01-Preview" \
                    -H "Authorization: Bearer $TOKEN" 2>/dev/null && echo "     ✅ Deleted indexer" || echo "     ❌ Indexer not found"
                
                # Delete skillset
                echo "   - Deleting pdf-skillset..."
                curl -s -X DELETE "https://$search_service.search.windows.net/skillsets/pdf-skillset?api-version=2025-11-01-Preview" \
                    -H "Authorization: Bearer $TOKEN" 2>/dev/null && echo "     ✅ Deleted skillset" || echo "     ❌ Skillset not found"
                
                # Delete index
                echo "   - Deleting pdf-index..."
                curl -s -X DELETE "https://$search_service.search.windows.net/indexes/pdf-index?api-version=2025-11-01-Preview" \
                    -H "Authorization: Bearer $TOKEN" 2>/dev/null && echo "     ✅ Deleted index" || echo "     ❌ Index not found"
                
                # Delete datasource  
                echo "   - Deleting pdf-datasource..."
                curl -s -X DELETE "https://$search_service.search.windows.net/datasources/pdf-datasource?api-version=2025-11-01-Preview" \
                    -H "Authorization: Bearer $TOKEN" 2>/dev/null && echo "     ✅ Deleted datasource" || echo "     ❌ Datasource not found"
                    
                echo "   ✅ Search pipeline cleanup completed"
            else
                echo "   ⚠️  Could not get search service access token. Skipping pipeline cleanup."
            fi
        else
            echo "   ⚠️  No Azure Search service found in resource group. Skipping pipeline cleanup."
        fi
    fi

    # Delete resource group
    echo ""
    echo "🗑️  Deleting resource group '$RESOURCE_GROUP_NAME'..."
    if ! az group delete --name "$RESOURCE_GROUP_NAME" --yes --no-wait; then
        echo "❌ Failed to delete resource group!"
        return 1
    fi
    echo "✅ Resource group deletion initiated (runs in background)"

    # Wait for deletion to complete if we need to purge
    if [[ "$PURGE_COGNITIVE" == "true" || "$PURGE_APIM" == "true" || "$PURGE_KEYVAULT" == "true" || "$PURGE_STORAGE" == "true" ]]; then
        echo ""
        echo "⏳ Waiting for resource group deletion to complete before purging..."
        az group wait --name "$RESOURCE_GROUP_NAME" --deleted --timeout 600 2>/dev/null || true
        # Extra wait — ARM can be slow to release soft-deleted resources
        sleep 10
    fi
fi

# Purge soft-deleted Cognitive Services (Azure AI Foundry)
if [[ "$PURGE_COGNITIVE" == "true" ]]; then
    echo ""
    echo "🔥 Purging soft-deleted Cognitive Services / AI Foundry resources..."
    deleted=$(az cognitiveservices account list-deleted --query "[].{name:name, location:location}" -o json 2>/dev/null || echo "[]")
    count=$(echo "$deleted" | jq length)

    if [[ "$count" -gt 0 ]]; then
        echo "   Found $count soft-deleted Cognitive Services resource(s):"
        echo "$deleted" | jq -r '.[] | "   - \(.name) (\(.location))"'
        echo ""
        echo "$deleted" | jq -c '.[]' | while read -r item; do
            name=$(echo "$item" | jq -r '.name')
            location=$(echo "$item" | jq -r '.location')
            echo "   Purging '$name' in $location..."
            # Soft-deleted resources are not tied to resource groups, so don't use --resource-group
            if az cognitiveservices account purge --name "$name" --location "$location" 2>/dev/null \
               || az rest --method DELETE --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/providers/Microsoft.CognitiveServices/locations/$location/deletedAccounts/$name?api-version=2023-05-01" 2>/dev/null; then
                echo "   ✅ Purged '$name'"
            else
                echo "   ⚠️  Could not purge '$name' — it may need more time or manual cleanup"
            fi
        done
    else
        echo "   No soft-deleted Cognitive Services resources found."
    fi
fi

# Purge soft-deleted APIM instances
if [[ "$PURGE_APIM" == "true" ]]; then
    echo ""
    echo "🔥 Purging soft-deleted API Management instances..."
    subscription_id=$(az account show --query "id" -o tsv)

    # List soft-deleted APIM services via REST API
    deleted_apim=$(az rest --method GET \
        --url "https://management.azure.com/subscriptions/$subscription_id/providers/Microsoft.ApiManagement/deletedservices?api-version=2022-08-01" \
        2>/dev/null || echo '{"value":[]}')
    count=$(echo "$deleted_apim" | jq '.value | length')

    if [[ "$count" -gt 0 ]]; then
        echo "   Found $count soft-deleted APIM instance(s):"
        echo "$deleted_apim" | jq -r '.value[] | "   - \(.name) (\(.location))"'
        echo ""
        echo "$deleted_apim" | jq -c '.value[]' | while read -r item; do
            name=$(echo "$item" | jq -r '.name')
            location=$(echo "$item" | jq -r '.location')
            echo "   Purging '$name' in $location..."
            if az rest --method DELETE \
                --url "https://management.azure.com/subscriptions/$subscription_id/providers/Microsoft.ApiManagement/locations/$location/deletedservices/$name?api-version=2022-08-01" \
                2>/dev/null; then
                echo "   ✅ Purged '$name'"
            else
                echo "   ⚠️  Could not purge '$name' — it may need more time or manual cleanup"
            fi
        done
    else
        echo "   No soft-deleted APIM instances found."
    fi
fi

# Purge soft-deleted Key Vaults
if [[ "$PURGE_KEYVAULT" == "true" ]]; then
    echo ""
    echo "🔥 Purging soft-deleted Key Vault instances..."
    subscription_id=$(az account show --query "id" -o tsv)

    # List soft-deleted Key Vaults
    deleted_kv=$(az keyvault list-deleted --query "[].{name:name, location:location, resourceId:properties.vaultId}" -o json 2>/dev/null || echo "[]")
    count=$(echo "$deleted_kv" | jq length)

    if [[ "$count" -gt 0 ]]; then
        echo "   Found $count soft-deleted Key Vault(s):"
        echo "$deleted_kv" | jq -r '.[] | "   - \(.name) (\(.location))"'
        echo ""
        echo "$deleted_kv" | jq -c '.[]' | while read -r item; do
            name=$(echo "$item" | jq -r '.name')
            location=$(echo "$item" | jq -r '.location')
            echo "   Purging '$name' in $location..."
            if az keyvault purge --name "$name" --location "$location" 2>/dev/null; then
                echo "   ✅ Purged '$name'"
            else
                echo "   ⚠️  Could not purge '$name' — it may need more time or manual cleanup"
            fi
        done
    else
        echo "   No soft-deleted Key Vault instances found."
    fi
fi

# Purge soft-deleted Storage Accounts
if [[ "$PURGE_STORAGE" == "true" ]]; then
    echo ""
    echo "🔥 Purging soft-deleted Storage Account instances..."
    subscription_id=$(az account show --query "id" -o tsv)

    # List soft-deleted Storage Accounts
    deleted_storage=$(az storage account list --include-deleted --query "[?deletedTime != null].{name:name, location:location, deletedTime:deletedTime}" -o json 2>/dev/null || echo "[]")
    count=$(echo "$deleted_storage" | jq length)

    if [[ "$count" -gt 0 ]]; then
        echo "   Found $count soft-deleted Storage Account(s):"
        echo "$deleted_storage" | jq -r '.[] | "   - \(.name) (\(.location)) deleted \(.deletedTime)"'
        echo ""
        echo "$deleted_storage" | jq -c '.[]' | while read -r item; do
            name=$(echo "$item" | jq -r '.name')
            location=$(echo "$item" | jq -r '.location')
            echo "   Purging '$name' in $location..."
            if az rest --method DELETE \
                --url "https://management.azure.com/subscriptions/$subscription_id/providers/Microsoft.Storage/locations/$location/deletedAccounts/$name?api-version=2022-09-01" \
                2>/dev/null; then
                echo "   ✅ Purged '$name'"
            else
                echo "   ⚠️  Could not purge '$name' — it may need more time or manual cleanup"
            fi
        done
    else
        echo "   No soft-deleted Storage Account instances found."
    fi
fi

# Summary
echo ""
echo "🧹 Cleanup complete!"
echo ""
echo "   Resource group '$RESOURCE_GROUP_NAME': Deletion initiated"
[[ "$PURGE_COGNITIVE" == "true" ]] && echo "   Cognitive Services (OpenAI): Purged"
[[ "$PURGE_APIM" == "true" ]] && echo "   API Management: Purged"
[[ "$PURGE_KEYVAULT" == "true" ]] && echo "   Key Vault: Purged"
[[ "$PURGE_STORAGE" == "true" ]] && echo "   Storage Account: Purged"
[[ "$CLEANUP_SEARCH_PIPELINE" == "true" ]] && echo "   Search Pipeline: Cleaned"
echo ""
echo "💡 Tips:"
echo "   - Deletion takes a few minutes to propagate"
echo "   - Check status: az group show --name $RESOURCE_GROUP_NAME 2>/dev/null || echo 'Deleted'"
echo "   - To redeploy: bash deploy.sh"

}

main "$@"
