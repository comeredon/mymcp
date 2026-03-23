# Copilot Instructions — PL/I to Java Translation

## Repository

PL/I source files (`PSAM1.pli`, `PSAM1LIB.pli`, `PSAM2.pli`) translated to Java 21 in `java-implementation/`.

## Entry Point

**Start with `AnalystAgent`** — it orchestrates the entire translation pipeline including all sub-agents.

---

## MCP Azure PDF Server

### Overview

The MCP server (`src/server.ts`) is a Node.js/Express application deployed as an Azure Container App behind API Management. It provides:

- **search** tool — Semantic + vector search across indexed PDF documents
- **fetch** tool — Retrieve full document content or specific pages by title or document ID
- REST API endpoints (`/api/search`, `/api/fetch`, `/health`)
- MCP protocol support (`/api/tools` — initialize, tools/list, tools/call)

### Architecture

```
GitHub Copilot / MCP Clients
         ↓
   [APIM Gateway] ← Public endpoint (Ocp-Apim-Subscription-Key)
         ↓
  [Container App] ← Internal only (x-api-key injected by APIM)
         ↓
  [Azure Services] ← AI Search (RBAC), Storage, AI Foundry (Managed Identity)
```

### Technology Stack

| Component | Technology |
|-----------|-----------|
| Runtime | Node.js 22, TypeScript, Express.js |
| Container | Docker (`node:22-alpine`), non-root user |
| Hosting | Azure Container Apps (internal ingress) |
| Gateway | Azure API Management (Consumption tier) |
| Search | Azure AI Search (RBAC-only, `disableLocalAuth: true`) |
| AI | Azure AI Foundry (`text-embedding-3-large`, `gpt-4o`) |
| Storage | Azure Blob Storage (`pdfs` container) |
| Infrastructure | Azure Bicep |
| Identity | Managed Identity with RBAC role assignments |
| Networking | Optional VNet with private endpoints |

### Key Operational Knowledge

- **Secrets are never in Bicep outputs** — retrieve via `az containerapp secret show` and `az rest` (APIM listSecrets)
- **Search uses RBAC-only** — API keys are disabled (`disableLocalAuth: true`); use `az account get-access-token --resource https://search.azure.com/`
- **Placeholder image on first deploy** — Bicep creates the Container App with `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest`; must update to real ACR image after push
- **Soft-deleted resources block name reuse** — Cognitive Services, APIM, Key Vault, Storage all use soft-delete; run `cleanup.sh --purge-all` before redeployment
- **WSL2 Docker credential fix** — If `docker-credential-desktop.exe: not found`, set `~/.docker/config.json` to `{"credsStore":""}` and use token-based ACR login
- **Fetch supports two lookup modes** — tries `text_document_id` first (base64 blob URL), falls back to `document_title` (e.g., `mg.pdf`)
- **No semantic configuration yet** — search code references `semantic-config` but the index doesn't have one; vector search works independently

### PdfMcpDevOpsAgent

Use `@PdfMcpDevOpsAgent` for all MCP server infrastructure tasks:
- Deploying/redeploying on Linux or Windows
- Cleaning up Azure resources
- Updating the Docker image
- Setting up the search pipeline
- Troubleshooting deployment issues
- Managing secrets and APIM configuration

---

## PL/I to Java Translation

### Agents

| Agent | File | Role |
|-------|------|------|
| **AnalystAgent** | `my-analyst.agent.md` | **Orchestrator.** Analyzes PL/I, creates specs, dispatches all sub-agents. |
| **DeveloperAgent** | `my-developer.agent.md` | Sub-agent. Implements Java 21 from specs. |
| **TesterAgent** | `my-tester.agent.md` | Sub-agent. Writes tests from specs. |
| **SecurityAgent** | `my-security.agent.md` | Sub-agent. Scans Java code for vulnerabilities. |
| **DiagramAgent** | `my-dagram.agend.md` | Sub-agent. Generates C4 PlantUML diagrams. |
| **DevOpsAgent** | `my-devops.agent.md` | Sub-agent. CI/CD, Docker, Azure deployment. |

### Skills

Reusable instructions in `.github/skills/`. Each agent's own file lists which skills it uses.

| Category | Skills |
|----------|--------|
| **orchestration** | `pipeline-flow`, `analysis-spec`, `sub-agent-dispatch`, `diagram-verification`, `reporting` |
| **development** | `implementation-workflow`, `java-patterns`, `type-mapping`, `record-parsing`, `data-generation`, `code-checklist`, `frontmatter-navigation` |
| **testing** | `test-planning`, `unit-testing`, `integration-testing`, `mocking`, `test-data`, `test-execution` |
| **security** | `code-scanning` |
| **diagrams** | `plantuml-links` |
| **build** | `build-validation` |
| **devops** | `docker`, `github-actions`, `azure-deployment`, `cicd-practices`, `terraform` |

## Key Conventions

- `BigDecimal` for all monetary values
- Composition over inheritance for I/O wrappers
- Compile and validate after every code change
- `custom-pli-mcp` server for PL/I language reference
