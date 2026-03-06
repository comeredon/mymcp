---
name: wsl2-environment-setup
description: Install and verify all dependencies for the MCP Azure PDF Server on Ubuntu running in WSL2. Use this skill to bootstrap a fresh MCP Azure PDF Server environment or diagnose missing prerequisites on Windows + WSL2.
---

# Environment Setup — Ubuntu on WSL2

## Overview

This skill installs and validates every dependency needed to build, containerize, and deploy the MCP Azure PDF Server from an Ubuntu WSL2 environment on Windows.

## 1. Check & Install Dependencies

Run each section in order. The scripts are idempotent — safe to re-run.

### Azure CLI

```bash
# Check
az --version 2>/dev/null && echo "✅ Azure CLI installed" || echo "❌ Azure CLI missing"

# Install (if missing)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

### Node.js 20 LTS & npm

```bash
# Check
node --version 2>/dev/null && npm --version 2>/dev/null && echo "✅ Node.js/npm installed" || echo "❌ Node.js/npm missing"

# Install (if missing) — NodeSource repo for Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
```

### Docker

Docker in WSL2 can run via **Docker Desktop for Windows** (recommended) or the native Docker Engine.

```bash
# Check
docker --version 2>/dev/null && echo "✅ Docker installed" || echo "❌ Docker missing"

# Option A: Docker Desktop for Windows (recommended)
#   1. Install Docker Desktop on Windows: https://docs.docker.com/desktop/install/windows-install/
#   2. Settings → Resources → WSL Integration → Enable for your Ubuntu distro
#   3. Restart WSL: wsl --shutdown (from PowerShell), then reopen Ubuntu

# Option B: Native Docker Engine in WSL2 (if Docker Desktop is not available)
sudo apt-get update
sudo apt-get install -y docker.io
sudo usermod -aG docker $USER
# Log out and back in, or run: newgrp docker
```

### jq (required by deploy.sh)

```bash
# Check
jq --version 2>/dev/null && echo "✅ jq installed" || echo "❌ jq missing"

# Install (if missing)
sudo apt-get install -y jq
```

## 2. Verify All Prerequisites

Run this block to confirm everything is ready:

```bash
echo "=== Environment Check ==="
echo ""

errors=0

check() {
  if command -v "$1" &>/dev/null; then
    echo "✅ $1 — $($1 --version 2>&1 | head -1)"
  else
    echo "❌ $1 — NOT FOUND"
    errors=$((errors + 1))
  fi
}

check az
check node
check npm
check docker
check jq

echo ""
if [ "$errors" -eq 0 ]; then
  echo "🎉 All prerequisites installed!"
else
  echo "⚠️  $errors tool(s) missing — install them above and re-run."
fi
```

## 3. Azure Login & Subscription

```bash
# Login
az login

# Verify
az account show --query "{subscription:name, user:user.name}" -o table

# (Optional) Set a specific subscription
# az account set --subscription "<subscription-name-or-id>"
```

## 4. Register Required Azure Resource Providers

Some providers may not be registered on a fresh subscription:

```bash
providers=(
  Microsoft.Search
  Microsoft.Storage
  Microsoft.CognitiveServices
  Microsoft.App
  Microsoft.ContainerRegistry
  Microsoft.OperationalInsights
  Microsoft.ManagedIdentity
  Microsoft.ApiManagement
  Microsoft.Network
)

for p in "${providers[@]}"; do
  state=$(az provider show -n "$p" --query "registrationState" -o tsv 2>/dev/null)
  if [ "$state" = "Registered" ]; then
    echo "✅ $p"
  else
    echo "⏳ Registering $p..."
    az provider register --namespace "$p" --wait
    echo "✅ $p registered"
  fi
done
```

## 5. Install Project Dependencies

```bash
cd /path/to/mymcp   # adjust to your workspace root

# Install npm packages
npm install

# Verify build
npm run build
```

## 6. Ready to Deploy

```bash
# Using Bash
./deploy.sh

# Or with options
./deploy.sh --resource-group "my-rg" --location "eastus" --deploy-apim
```

## 7. Validate Deployment

After deployment completes, verify everything is configured correctly:

```bash
./validate-deployment.sh --resource-group mcp-server-rg
```

This checks:
- All required resources exist (Container App, ACR, Search, Storage, OpenAI, etc.)
- Container app is running
- Storage containers (`pdfs`, `documents`) exist
- OpenAI deployments (`embeddings`, `chat`) exist
- Managed identity role assignments are in place
- Health endpoint is responding
- APIM gateway is configured (if deployed)

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `npm: command not found` | Install Node.js (see step 1) or open a new terminal |
| `docker: command not found` | Enable WSL integration in Docker Desktop, or install Docker Engine |
| `docker: permission denied` | Run `sudo usermod -aG docker $USER` then log out and back in |
| `az: command not found` | Install Azure CLI (see step 1) |
| `jq: command not found` | `sudo apt-get install -y jq` |
| `Cannot connect to Docker daemon` | Start Docker Desktop on Windows, or run `sudo service docker start` |
| `az login` hangs in WSL | Try `az login --use-device-code` |
| Node.js version too old | Remove old version: `sudo apt-get remove nodejs && sudo apt-get autoremove`, then reinstall from NodeSource |

## WSL2-Specific Notes

- **File paths**: Use `/mnt/c/...` to access Windows files, but keep the project repo inside WSL (e.g., `~/workspace/`) for best performance.
- **Networking**: WSL2 shares the host network. `localhost` in WSL2 maps to the Windows host.
- **Docker Desktop**: Must have "Use the WSL 2 based engine" enabled in Settings → General.
- **Memory**: If builds are slow, increase WSL memory in `%USERPROFILE%\.wslconfig`:
  ```ini
  [wsl2]
  memory=8GB
  processors=4
  ```
  Then restart WSL: `wsl --shutdown` from PowerShell.
