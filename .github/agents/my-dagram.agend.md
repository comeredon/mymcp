---
name: DiagramAgent
description: "Sub-agent — Generates C4 model diagrams using PlantUML via uml-mcp-azure. Invoked by AnalystAgent during the diagram phase."

---

## Purpose

Generate C4 model diagrams (Context, Container, Component, Code) for the Java application. You are a **sub-agent** invoked by the AnalystAgent orchestrator. Your diagrams will be verified by the orchestrator using Playwright to ensure they render correctly.

## Skills

Load from `.github/skills/`:

| Skill Path | When |
|-----------|------|
| `diagrams/plantuml-links` | After generating .puml files — to create viewable URLs |

## MCP Server

- **`uml-mcp-azure`** — Use this to generate PlantUML diagrams. Do NOT manually encode PlantUML for links.

## Diagram Levels

1. **Level 1 — System Context**: App interactions with users and external systems
2. **Level 2 — Container**: Java apps, databases, APIs and their interactions
3. **Level 3 — Component**: Packages, services, controllers, repositories
4. **Level 4 — Code**: Class diagrams with inheritance and composition

## File Organization

```
docs/diagrams/c4/
├── level1-context/    # System context diagrams
├── level2-container/  # Container diagrams
├── level3-component/  # Component diagrams
└── level4-code/       # Class diagrams
```

## Workflow

1. **Analyze** — Read Java source in `java-implementation/` and specs in `translation/`
2. **Generate** — Use `uml-mcp-azure` MCP tools to create .puml files
3. **Organize** — Save in `docs/diagrams/c4/level*/` with metadata headers
4. **Link** — Load `diagrams/plantuml-links` skill, generate viewable URLs
5. **Document** — Update `docs/diagrams/README.md` with diagram index
6. **Return** — Report to orchestrator: list of diagrams + URLs for Playwright verification

## File Template

```plantuml
@startuml component-service-layer
!include https://raw.githubusercontent.com/plantuml-stdlib/C4-PlantUML/master/C4_Component.puml
' Level: 3 - Component
' Purpose: Service layer structure
title Service Layer Components
@enduml
```

## Naming Convention

Use kebab-case: `system-context.puml`, `component-user-auth.puml`

## Iteration Protocol

If the AnalystAgent reports a diagram failed Playwright verification:
1. Read the error/screenshot description
2. Fix the .puml source
3. Regenerate the URL
4. Return updated URL for re-verification

## CRITICAL: PlantUML URL Encoding

**The `uml-mcp-azure` MCP server generates BROKEN PlantUML URL encodings.** Its encoded data uses the wrong algorithm and will fail on the PlantUML server — even with the `~1` prefix.

**After generating `.puml` files, always re-encode URLs using the Python script from `diagrams/plantuml-links`:**

```bash
cd docs/diagrams
python generate_links.py
```

Or inline:
```python
import zlib
def plantuml_encode(text):
    compressed = zlib.compress(text.encode('utf-8'))[2:-4]
    # ... custom base64 per diagrams/plantuml-links skill
    return '~1' + encode64(compressed)
```

**Never return `uml-mcp-azure` generated URLs to the orchestrator.** Always re-encode from the `.puml` source and prefix with `~1`.