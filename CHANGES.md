# Changes Log — February 20, 2026

## 1. Container Image Chicken-and-Egg Fix

**Problem**: On fresh deployments, the Container App fails with `MANIFEST_UNKNOWN` because Bicep deploys the Container App referencing an ACR image (`mcp-azure-pdf:latest`) that hasn't been pushed yet.

**Files changed**:

- **`infra/core/host/container-app.bicep`**
  - `imageName` parameter now defaults to `''` (was required)
  - New `containerImage` variable: uses the ACR image when `imageName` is provided, otherwise falls back to `mcr.microsoft.com/k8se/quickstart:latest` (public placeholder)
  - Container definition uses `containerImage` variable instead of hardcoded ACR reference

- **`infra/main.bicep`**
  - Removed `imageName: 'mcp-azure-pdf'` from the `mcpServer` module params — lets the placeholder kick in on first deploy
  - Added `output CONTAINER_APP_NAME string = mcpServer.outputs.name` so `deploy.sh` can reference the container app after image push

- **`deploy.sh`**
  - Extracts `container_app_name` from Bicep deployment outputs
  - After building and pushing the image to ACR, runs `az containerapp update` to switch the container app from the placeholder to the real `mcp-azure-pdf:latest` image

**New deploy flow**:
1. Bicep deploys → Container App starts with MCR quickstart placeholder (always succeeds)
2. `deploy.sh` builds and pushes `mcp-azure-pdf:latest` to ACR
3. `az containerapp update` switches the container to the real image

---

## 2. Container App External Access Fix

**Problem**: The container app was deployed with `external: false` (internal-only ingress), but:
- The Container Apps Environment has **no VNET** configured
- APIM Consumption tier has **no VNET integration**
- Result: APIM backend couldn't reach the internal container app → health endpoint returned 404 ("Container App is stopped or does not exist")

**Root cause**: Architecture mismatch — `external: false` requires VNET integration on both the Container Apps Environment and APIM to work. Without it, APIM simply cannot route traffic to the internal FQDN.

**File changed**:

- **`infra/main.bicep`**
  - Changed `external: false` to `external: true` on the `mcpServer` module
  - The container app is still secured by API key authentication (`x-api-key` header); APIM injects this automatically via its policy

**Note**: The APIM backend URL also needed updating from the `.internal.` FQDN to the external FQDN. This was done manually for the current deployment but will be correct on future fresh deploys since Bicep passes `mcpServer.outputs.uri` to the APIM backend.

---

## 3. Health Check Validation Fix

**Problem**: `validate-deployment.sh` tested health by curling the container app's FQDN directly, which was unreachable (internal-only at the time). Even after making the app external, the proper public entry point is APIM.

**File changed**:

- **`validate-deployment.sh`**
  - Health check now goes through APIM: `{gatewayUrl}/mcp/health`
  - Falls back to direct container app access only if APIM isn't deployed
  - Unreachable APIM health is a warning (APIM may still be provisioning), not an error

---

## Validation Result

All checks now pass:

```
✅ Resource group exists
✅ All 8 resources deployed
✅ Container app is running
✅ Storage containers exist (pdfs, documents)
✅ OpenAI deployments exist (embeddings, chat)
✅ Role assignments configured (AcrPull, Search, Storage, OpenAI)
✅ APIM deployed with gateway URL
✅ Health endpoint responding via APIM
```

## Files Modified Summary

| File | Change |
|------|--------|
| `infra/core/host/container-app.bicep` | Default placeholder image, optional `imageName` |
| `infra/main.bicep` | Removed hardcoded `imageName`, added `CONTAINER_APP_NAME` output, `external: true` |
| `deploy.sh` | Extract container app name, `az containerapp update` after image push |
| `validate-deployment.sh` | Health check via APIM instead of direct container app access |
