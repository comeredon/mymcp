# Copilot Instructions — PL/I to Java Translation

## Repository

PL/I source files (`PSAM1.pli`, `PSAM1LIB.pli`, `PSAM2.pli`) translated to Java 21 in `java-implementation/`.

## Entry Point

**Start with `AnalystAgent`** — it orchestrates the entire translation pipeline including all sub-agents.

## Agents

| Agent | File | Role |
|-------|------|------|
| **AnalystAgent** | `my-analyst.agent.md` | **Orchestrator.** Analyzes PL/I, creates specs, dispatches all sub-agents. |
| **DeveloperAgent** | `my-developer.agent.md` | Sub-agent. Implements Java 21 from specs. |
| **TesterAgent** | `my-tester.agent.md` | Sub-agent. Writes tests from specs. |
| **SecurityAgent** | `my-security.agent.md` | Sub-agent. Scans Java code for vulnerabilities. |
| **DiagramAgent** | `my-dagram.agend.md` | Sub-agent. Generates C4 PlantUML diagrams. |
| **DevOpsAgent** | `my-devops.agent.md` | Sub-agent. CI/CD, Docker, Azure deployment. |

## Skills

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
