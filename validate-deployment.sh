#!/usr/bin/env bash
# Deployment Validation Script
# Run this after deployment to verify everything is configured correctly

main() {
set -euo pipefail

# Default parameters
RESOURCE_GROUP_NAME=""

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --resource-group) RESOURCE_GROUP_NAME="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 --resource-group <name>"
            echo ""
            echo "Options:"
            echo "  --resource-group NAME   Resource group to validate (required)"
            echo "  -h, --help              Show this help message"
            return 0
            ;;
        *) echo "Unknown option: $1"; return 1 ;;
    esac
done

if [[ -z "$RESOURCE_GROUP_NAME" ]]; then
    echo "❌ --resource-group is required"
    echo "Usage: $0 --resource-group <name>"
    return 1
fi

errors=0
warnings=0

echo "🔍 Validating MCP Deployment"
echo "================================"
echo ""

# Check resource group exists
echo "Checking resource group..."
if ! az group show --name "$RESOURCE_GROUP_NAME" --output none 2>/dev/null; then
    echo "❌ Resource group '$RESOURCE_GROUP_NAME' not found"
    return 1
fi
rg_name=$(az group show --name "$RESOURCE_GROUP_NAME" --query "name" -o tsv)
echo "✅ Resource group exists: $rg_name"

# Get all resources
echo ""
echo "Checking deployed resources..."
resources=$(az resource list --resource-group "$RESOURCE_GROUP_NAME" \
    --query "[].{name:name, type:type}" -o json)

# Required resources — check each one
check_resource() {
    local resource_type="$1"
    local display_name="$2"
    local name
    name=$(echo "$resources" | jq -r ".[] | select(.type == \"$resource_type\") | .name" | head -1)
    if [[ -n "$name" ]]; then
        echo "✅ $display_name: $name"
    else
        echo "❌ $display_name not found"
        errors=$((errors + 1))
    fi
}

check_resource "Microsoft.OperationalInsights/workspaces"          "Log Analytics Workspace"
check_resource "Microsoft.ManagedIdentity/userAssignedIdentities"  "Managed Identity"
check_resource "Microsoft.ContainerRegistry/registries"            "Container Registry"
check_resource "Microsoft.App/managedEnvironments"                 "Container Apps Environment"
check_resource "Microsoft.App/containerApps"                       "Container App"
check_resource "Microsoft.Search/searchServices"                   "AI Search Service"
check_resource "Microsoft.Storage/storageAccounts"                 "Storage Account"
check_resource "Microsoft.CognitiveServices/accounts"              "Azure OpenAI"

# Check container app status
echo ""
echo "Checking container app status..."
container_app_name=$(echo "$resources" | jq -r '.[] | select(.type == "Microsoft.App/containerApps") | .name' | head -1)
if [[ -n "$container_app_name" ]]; then
    app_status=$(az containerapp show --name "$container_app_name" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --query "properties.runningStatus" -o tsv 2>/dev/null || echo "Unknown")
    if [[ "$app_status" == "Running" ]]; then
        echo "✅ Container app is running"
    else
        echo "⚠️  Container app status: $app_status"
        warnings=$((warnings + 1))
    fi
fi

# Check storage containers
echo ""
echo "Checking storage containers..."
storage_name=$(echo "$resources" | jq -r '.[] | select(.type == "Microsoft.Storage/storageAccounts") | .name' | head -1)
if [[ -n "$storage_name" ]]; then
    containers=$(az storage container list --account-name "$storage_name" \
        --auth-mode login --query "[].name" -o json 2>/dev/null || echo "[]")
    for c in pdfs documents; do
        if echo "$containers" | jq -e ".[] | select(. == \"$c\")" >/dev/null 2>&1; then
            echo "✅ '$c' container exists"
        else
            echo "⚠️  '$c' container not found"
            warnings=$((warnings + 1))
        fi
    done
fi

# Check Azure OpenAI deployments
echo ""
echo "Checking Azure OpenAI deployments..."
openai_name=$(echo "$resources" | jq -r '.[] | select(.type == "Microsoft.CognitiveServices/accounts") | .name' | head -1)
if [[ -n "$openai_name" ]]; then
    deployments=$(az cognitiveservices account deployment list --name "$openai_name" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --query "[].name" -o json 2>/dev/null || echo "[]")
    for d in embeddings chat; do
        if echo "$deployments" | jq -e ".[] | select(. == \"$d\")" >/dev/null 2>&1; then
            echo "✅ '$d' deployment exists"
        else
            echo "⚠️  '$d' deployment not found"
            warnings=$((warnings + 1))
        fi
    done
fi

# Check role assignments
echo ""
echo "Checking role assignments..."
identity_name=$(echo "$resources" | jq -r '.[] | select(.type == "Microsoft.ManagedIdentity/userAssignedIdentities") | .name' | head -1)
if [[ -n "$identity_name" ]]; then
    principal_id=$(az identity show --name "$identity_name" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --query "principalId" -o tsv 2>/dev/null || true)
    if [[ -n "$principal_id" ]]; then
        role_assignments=$(az role assignment list --assignee "$principal_id" \
            --resource-group "$RESOURCE_GROUP_NAME" \
            --query "[].roleDefinitionName" -o json 2>/dev/null || echo "[]")
        for role in "AcrPull" "Search Index Data Contributor" "Storage Blob Data Contributor" "Cognitive Services OpenAI User"; do
            if echo "$role_assignments" | jq -e ".[] | select(. == \"$role\")" >/dev/null 2>&1; then
                echo "✅ Role assigned: $role"
            else
                echo "⚠️  Role not assigned: $role"
                warnings=$((warnings + 1))
            fi
        done
    else
        echo "⚠️  Could not retrieve managed identity details"
        warnings=$((warnings + 1))
    fi
fi

# Check APIM and test health endpoint through it
apim_name=$(echo "$resources" | jq -r '.[] | select(.type == "Microsoft.ApiManagement/service") | .name' | head -1)
if [[ -n "$apim_name" ]]; then
    echo ""
    echo "Checking API Management..."
    echo "✅ APIM deployed: $apim_name"
    apim_gateway=$(az apim show --name "$apim_name" \
        --resource-group "$RESOURCE_GROUP_NAME" \
        --query "gatewayUrl" -o tsv 2>/dev/null || true)
    if [[ -n "$apim_gateway" ]]; then
        echo "✅ Gateway URL: $apim_gateway"

        # Test health through APIM (the container app is internal-only, not reachable directly)
        echo ""
        echo "Testing health endpoint via APIM..."
        health_url="${apim_gateway}/mcp/health"
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "$health_url" 2>/dev/null || echo "000")
        if [[ "$http_code" == "200" ]]; then
            echo "✅ Health endpoint responding: $health_url"
        elif [[ "$http_code" == "000" ]]; then
            echo "⚠️  Health endpoint not reachable (APIM may still be provisioning): $health_url"
            warnings=$((warnings + 1))
        else
            echo "⚠️  Health endpoint returned HTTP $http_code: $health_url"
            warnings=$((warnings + 1))
        fi
    fi
else
    # No APIM — try direct access (only works if container app has external: true)
    echo ""
    echo "Testing health endpoint (direct)..."
    if [[ -n "$container_app_name" ]]; then
        app_fqdn=$(az containerapp show --name "$container_app_name" \
            --resource-group "$RESOURCE_GROUP_NAME" \
            --query "properties.configuration.ingress.fqdn" -o tsv 2>/dev/null || true)
        if [[ -n "$app_fqdn" ]]; then
            health_url="https://$app_fqdn/health"
            http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$health_url" 2>/dev/null || echo "000")
            if [[ "$http_code" == "200" ]]; then
                echo "✅ Health endpoint responding: $health_url"
            elif [[ "$http_code" == "000" ]]; then
                echo "❌ Health endpoint not accessible: $health_url"
                errors=$((errors + 1))
            else
                echo "⚠️  Health endpoint returned HTTP $http_code: $health_url"
                warnings=$((warnings + 1))
            fi
        fi
    fi
fi

# Summary
echo ""
echo "================================"
echo "📊 Validation Summary"
echo "================================"

if [[ "$errors" -eq 0 && "$warnings" -eq 0 ]]; then
    echo "✅ All checks passed!"
    echo ""
    echo "Your deployment is ready to use!"
elif [[ "$errors" -eq 0 ]]; then
    echo ""
    echo "⚠️  Warnings ($warnings):"
    echo "   Deployment has warnings but should be functional."
else
    echo ""
    echo "❌ Errors: $errors"
    echo "⚠️  Warnings: $warnings"
    echo ""
    echo "Please address the errors before using the deployment."
    return 1
fi

}

main "$@"
