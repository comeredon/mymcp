# Copilot Instructions for PL/I to Java Translation Project

## Project Overview

This repository contains PL/I source code (PSAM1.pli, PSAM1LIB.pli, PSAM2.pli) that needs to be translated to Java 21. The project uses specialized AI agents and reusable skills to analyze PL/I code, create specifications, implement Java equivalents, validate through testing, scan for security issues, and manage deployment.


## Repository Structure

```
pl1ref/
├── PSAM1.pli                          # Main PL/I program (reads files, writes reports)
├── PSAM1LIB.pli                       # PL/I library module (shared functions)
├── PSAM2.pli                          # Secondary PL/I program
├── .github/
│   ├── copilot-instructions.md        # This file
│   ├── agents/                        # Custom AI agents
│   │   ├── my-pm.agent.md             # ProgramManager — PL/I analysis & documentation
│   │   ├── my-developer.agent.md      # DeveloperAgent — Java 21 implementation
│   │   ├── my-tester.agent.md         # TesterAgent — testing & validation
│   │   ├── my-security.agent.md       # SecurityAgent — vulnerability scanning
│   │   ├── my-devops.agent.md         # DevOpsAgent — CI/CD & deployment
│   │   └── my-dagram.agend.md         # DiagramAgent — C4 architecture diagrams
│   ├── skills/                        # Reusable skills (Agent Skills standard)
│   │   ├── build/build-validation/    # Maven build & validation workflow
│   │   ├── development/               # Implementation patterns & type mapping
│   │   ├── testing/                   # JUnit 5, mocking, coverage, test data
│   │   ├── devops/                    # Docker, GitHub Actions, Azure, CI/CD
│   │   ├── diagrams/plantuml-links/   # PlantUML URL generation
│   │   └── security/code-scanning/    # OWASP, dependency & container scanning
│   └── workflows/                     # GitHub Actions (agentic workflows)
│       ├── update-readme.md           # Auto-update README on push to main
│       └── security-review-java.md    # Security scan on Java code pushes
├── translation/                       # Created by ProgramManager agent
│   ├── INDEX.md                       # Auto-generated navigation index
│   ├── overview.md
│   ├── architecture.md
│   ├── variables-psam1.md
│   ├── variables-psam1lib.md
│   ├── variables-psam2.md
│   ├── record-formats.md
│   ├── data-types.md
│   ├── logic-psam1.md
│   ├── logic-psam1lib.md
│   ├── logic-psam2.md
│   ├── control-flow.md
│   ├── file-io.md
│   ├── report-layouts.md
│   ├── input-formats.md
│   ├── error-handling.md
│   ├── dependencies.md
│   ├── special-considerations.md
│   ├── picture-formats.md
│   └── string-handling.md
└── java-implementation/               # Created by DeveloperAgent
```

## Agents

Each agent is defined in `.github/agents/` with YAML frontmatter specifying `name`, `description`, `model`, and optional `handoffs`.

### Core Translation Agents

| Agent | File | Purpose |
|-------|------|---------|
| **ProgramManager** | `my-pm.agent.md` | Analyzes PL/I code using `custom-pli-mcp` server and creates detailed documentation in `translation/`. Never writes Java code. Hands off to DeveloperAgent. |
| **DeveloperAgent** | `my-developer.agent.md` | Implements Java 21 code from specifications in `translation/`. Follows development skills for patterns, type mapping, and record parsing. Compiles after every file change. |
| **TesterAgent** | `my-tester.agent.md` | Validates Java implementations with unit, integration, and E2E tests. Targets: Data Models 95%, Business Logic 90%, I/O 80%, Utilities 70% coverage. Reports bugs but does not fix production code. |

### Supporting Agents

| Agent | File | Purpose |
|-------|------|---------|
| **SecurityAgent** | `my-security.agent.md` | SAST, SCA, infrastructure, and compliance analysis. Scans `java-implementation/` only. Produces `security-reports/security-report.md`. |
| **DevOpsAgent** | `my-devops.agent.md` | CI/CD pipelines (GitHub Actions), Docker containerization, Azure deployment. Uses `eclipse-temurin:21-jre-alpine` base image. |
| **DiagramAgent** | `my-dagram.agend.md` | Generates C4 model diagrams (Context, Container, Component, Code) as PlantUML files in `docs/diagrams/c4/`. |

## Skills

Skills are stored in `.github/skills/` following the [Agent Skills standard](https://github.com/agentskills/agentskills). Each skill folder contains a `SKILL.md` with focused, reusable instructions. Agents load skills dynamically based on the task.

| Category | Skills | Used By |
|----------|--------|---------|
| **development** | `implementation-workflow`, `java-patterns`, `type-mapping`, `record-parsing`, `data-generation`, `code-checklist`, `frontmatter-navigation` | DeveloperAgent, ProgramManager |
| **testing** | `test-planning`, `unit-testing`, `integration-testing`, `mocking`, `test-data`, `test-execution` | TesterAgent |
| **devops** | `docker`, `github-actions`, `azure-deployment`, `cicd-practices` | DevOpsAgent |
| **build** | `build-validation` | DeveloperAgent, DevOpsAgent |
| **security** | `code-scanning` | SecurityAgent, DevOpsAgent |
| **diagrams** | `plantuml-links` | DiagramAgent |

## Translation Workflow

The complete PL/I to Java translation follows this process:

1. **Analysis** — ProgramManager analyzes PL/I source files using the `custom-pli-mcp` server
2. **Documentation** — ProgramManager creates granular specification files in `translation/` with YAML frontmatter and generates `INDEX.md` as a navigation hub
3. **Implementation** — DeveloperAgent uses frontmatter navigation to read specifications and implement Java 21 code in `java-implementation/`
4. **Testing** — TesterAgent creates and runs tests to validate correctness against PL/I behavior
5. **Security** — SecurityAgent scans the Java implementation for vulnerabilities
6. **Deployment** — DevOpsAgent sets up CI/CD pipelines and containerized deployment

## Automated Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| **update-readme** | Push to `main` | Analyzes repo structure and creates a PR to update `README.md` |
| **security-review-java** | Push to `main` (commit message contains "adding java") | Runs SecurityAgent scan, then DeveloperAgent fixes if vulnerabilities found; creates a PR |

Both workflows use the agentic workflow format (compiled via `gh aw compile`) with safe outputs for PR creation, noop, and error transparency.

## General Guidelines

- Use the appropriate agent for each task — agents have distinct responsibilities
- ProgramManager: Only creates documentation, never writes Java code
- DeveloperAgent: Only implements Java, never modifies PL/I source files
- TesterAgent: Reports bugs but does not fix production code
- Agents collaborate through documentation in `translation/` and handoffs
- Skills in `.github/skills/` provide reusable implementation patterns — consult them before starting work
- When in doubt, ask for clarification rather than making assumptions
- Use `BigDecimal` for all monetary/decimal values, composition over inheritance for I/O wrappers
- Compile and validate after every code change

## Custom MCP Server

The `custom-pli-mcp` server is available for PL/I code analysis. Use it for:
- Understanding PL/I syntax, semantics, and built-in functions
- Analyzing program flow, control structures, and data declarations
- Clarifying PL/I-specific constructs (e.g., `PICTURE`, `BASED`, `CONDITION` handling)
- Verifying interpretations of business logic and edge cases
