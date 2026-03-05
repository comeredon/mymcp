# Copilot Instructions

This repository serves two purposes:

1. **PL/I to Java Translation** — Translating PL/I source code (in `pli_src/`) to Java 21 using specialized AI agents
2. **MCP Azure PDF Server** — A Model Context Protocol (MCP) server that indexes PDF documents in Azure AI Search and exposes search/fetch tools for GitHub Copilot agents

---

## Repository Structure

```
mymcp/
├── src/server.ts                      # MCP server (Express.js + Azure SDK)
├── Dockerfile                         # Container build (node:22-alpine)
├── package.json / tsconfig.json       # Node.js project config
├── infra/                             # Azure Bicep infrastructure templates
│   ├── main.bicep                     # Main template (all resources)
│   └── core/                          # Resource modules (AI, gateway, host, etc.)
├── deploy.sh / deploy.ps1             # Unified deployment scripts (Linux / Windows)
├── cleanup.sh / cleanup.ps1           # Cleanup + purge scripts (Linux / Windows)
├── setup-search-pipeline.sh/.ps1      # AI Search pipeline (data source, index, skillset, indexer)
├── validate-deployment.sh/.ps1        # Post-deployment validation
├── TODO.md                            # Project backlog
├── pli_src/                           # PL/I source code (gitignored, not committed)
├── .github/
│   ├── copilot-instructions.md        # This file
│   ├── agents/                        # Custom AI agents
│   │   ├── my-pm.agent.md             # ProgramManager — PL/I analysis & documentation
│   │   ├── my-developer.agent.md      # DeveloperAgent — Java 21 implementation
│   │   ├── my-tester.agent.md         # TesterAgent — testing & validation
│   │   ├── my-security.agent.md       # SecurityAgent — vulnerability scanning
│   │   ├── my-devops.agent.md         # DevOpsAgent — CI/CD for Java translation
│   │   ├── my-pdf-mcp-devops.agent.md # PdfMcpDevOpsAgent — MCP server deployment & ops
│   │   └── my-dagram.agend.md         # DiagramAgent — C4 architecture diagrams
│   ├── skills/                        # Reusable skills (Agent Skills standard)
│   │   ├── build/build-validation/    # Maven / npm build & validation workflow
│   │   ├── development/               # Implementation patterns & type mapping
│   │   ├── testing/                   # JUnit 5, mocking, coverage, test data
│   │   ├── devops/                    # Docker, GitHub Actions, Azure, CI/CD, resource purging
│   │   ├── quickstart/               # MCP server deployment & cleanup guides
│   │   │   ├── wsl2-environment-setup/  # Prerequisites install on WSL2
│   │   │   ├── deployment-linux/        # Step-by-step deploy on Linux / WSL2
│   │   │   ├── deployment-windows/      # Step-by-step deploy on Windows / PowerShell
│   │   │   ├── cleanup-linux/           # Step-by-step cleanup on Linux / WSL2
│   │   │   ├── cleanup-windows/         # Step-by-step cleanup on Windows / PowerShell
│   │   │   ├── wsl2-cleanup/            # Legacy cleanup reference
│   │   ├── diagrams/plantuml-links/   # PlantUML URL generation
│   │   └── security/code-scanning/    # OWASP, dependency & container scanning
│   └── workflows/                     # GitHub Actions (agentic workflows)
│       ├── update-readme.md           # Auto-update README on push to main
│       └── security-review-java.md    # Security scan on Java code pushes
├── translation/                       # Created by ProgramManager agent
│   └── *.md                           # Specification documents
└── java-implementation/               # Created by DeveloperAgent
```

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

Each agent is defined in `.github/agents/` with YAML frontmatter specifying `name`, `description`, `model`, and optional `handoffs`.

#### Core Translation Agents

| Agent | File | Purpose |
|-------|------|---------|
| **ProgramManager** | `my-pm.agent.md` | Analyzes PL/I code using `custom-pli-mcp` server and creates detailed documentation in `translation/`. Never writes Java code. Hands off to DeveloperAgent. |
| **DeveloperAgent** | `my-developer.agent.md` | Implements Java 21 code from specifications in `translation/`. Follows development skills for patterns, type mapping, and record parsing. Compiles after every file change. |
| **TesterAgent** | `my-tester.agent.md` | Validates Java implementations with unit, integration, and E2E tests. Targets: Data Models 95%, Business Logic 90%, I/O 80%, Utilities 70% coverage. Reports bugs but does not fix production code. |

#### Supporting Agents

| Agent | File | Purpose |
|-------|------|---------|
| **SecurityAgent** | `my-security.agent.md` | SAST, SCA, infrastructure, and compliance analysis. Scans `java-implementation/` only. Produces `security-reports/security-report.md`. |
| **DevOpsAgent** | `my-devops.agent.md` | CI/CD pipelines (GitHub Actions), Docker containerization, Azure deployment for the **Java translation**. Uses `eclipse-temurin:21-jre-alpine`. |
| **PdfMcpDevOpsAgent** | `my-pdf-mcp-devops.agent.md` | Deployment, cleanup, Docker, and infrastructure management for the **MCP Azure PDF Server**. Uses `node:22-alpine`. |
| **DiagramAgent** | `my-dagram.agend.md` | Generates C4 model diagrams (Context, Container, Component, Code) as PlantUML files in `docs/diagrams/c4/`. |

### Skills

Skills are stored in `.github/skills/` following the [Agent Skills standard](https://github.com/agentskills/agentskills). Each skill folder contains a `SKILL.md` with focused, reusable instructions. Agents load skills dynamically based on the task.

| Category | Skills | Used By |
|----------|--------|---------|
| **development** | `implementation-workflow`, `java-patterns`, `type-mapping`, `record-parsing`, `data-generation`, `code-checklist`, `frontmatter-navigation` | DeveloperAgent, ProgramManager |
| **testing** | `test-planning`, `unit-testing`, `integration-testing`, `mocking`, `test-data`, `test-execution` | TesterAgent |
| **devops** | `docker`, `github-actions`, `azure-deployment`, `cicd-practices`, `azure-resource-purging` | DevOpsAgent, PdfMcpDevOpsAgent |
| **quickstart** | `wsl2-environment-setup`, `deployment-linux`, `deployment-windows`, `cleanup-linux`, `cleanup-windows`, `wsl2-cleanup` | PdfMcpDevOpsAgent |
| **build** | `build-validation` | DeveloperAgent, DevOpsAgent, PdfMcpDevOpsAgent |
| **security** | `code-scanning` | SecurityAgent, DevOpsAgent |
| **diagrams** | `plantuml-links` | DiagramAgent |

### Translation Workflow

1. **Analysis** — ProgramManager analyzes PL/I source files using the `custom-pli-mcp` server
2. **Documentation** — ProgramManager creates granular specification files in `translation/` with YAML frontmatter and generates `INDEX.md` as a navigation hub
3. **Implementation** — DeveloperAgent uses frontmatter navigation to read specifications and implement Java 21 code in `java-implementation/`
4. **Testing** — TesterAgent creates and runs tests to validate correctness against PL/I behavior
5. **Security** — SecurityAgent scans the Java implementation for vulnerabilities
6. **Deployment** — DevOpsAgent sets up CI/CD pipelines and containerized deployment

### Custom MCP Server for PL/I Analysis

The `custom-pli-mcp` server (deployed via PdfMcpDevOpsAgent) is available for PL/I code analysis. Use it for:
- Understanding PL/I syntax, semantics, and built-in functions
- Analyzing program flow, control structures, and data declarations
- Clarifying PL/I-specific constructs (e.g., `PICTURE`, `BASED`, `CONDITION` handling)
- Verifying interpretations of business logic and edge cases

---

## Automated Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| **update-readme** | Push to `main` | Analyzes repo structure and creates a PR to update `README.md` |
| **security-review-java** | Push to `main` (commit message contains "adding java") | Runs SecurityAgent scan, then DeveloperAgent fixes if vulnerabilities found; creates a PR |

Both workflows use the agentic workflow format (compiled via `gh aw compile`) with safe outputs for PR creation, noop, and error transparency.

## General Guidelines

- Use the appropriate agent for each task — agents have distinct responsibilities
- **PdfMcpDevOpsAgent** for MCP server deployment/ops; **DevOpsAgent** for Java translation CI/CD
- ProgramManager: Only creates documentation, never writes Java code
- DeveloperAgent: Only implements Java, never modifies PL/I source files
- TesterAgent: Reports bugs but does not fix production code
- Agents collaborate through documentation in `translation/` and handoffs
- Skills in `.github/skills/` provide reusable implementation patterns — consult them before starting work
- When in doubt, ask for clarification rather than making assumptions
- Use `BigDecimal` for all monetary/decimal values, composition over inheritance for I/O wrappers
- Compile and validate after every code change
- Never commit secrets to git — retrieve at runtime via Azure CLI
- See `TODO.md` for the project backlog (granular extraction, private networking, AI Foundry migration, Content Understanding evaluation)
