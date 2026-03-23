---
name: analysis-spec
description: "Documentation output format for PL/I analysis. Defines frontmatter schema, file structure, and INDEX.md layout. Used by AnalystAgent in Phase 1."
---

# Analysis Documentation Specification

> **Related skills:** `development/frontmatter-navigation`, `development/type-mapping`

## Frontmatter Format

Every file in `translation/` must start with this YAML frontmatter:

```yaml
---
title: "<Descriptive title>"
category: "<overview|data-structures|business-logic|io-operations|error-handling|dependencies|special-considerations>"
source_files: ["PSAM1.pli"]
tags: ["relevant", "keywords"]
related_docs: ["other-file.md"]
priority: 1-5
summary: "<One-line summary>"
last_analyzed: "YYYY-MM-DD"
---
```

## File Structure

Break into **concise, focused files** — one topic per file.

| File | Category | Content |
|------|----------|---------|
| `overview.md` | overview | Application purpose and high-level architecture |
| `architecture.md` | overview | Program structure, module relationships, execution flow |
| `variables-psam1.md` | data-structures | All variables declared in PSAM1.pli |
| `variables-psam1lib.md` | data-structures | All variables declared in PSAM1LIB.pli |
| `variables-psam2.md` | data-structures | All variables declared in PSAM2.pli |
| `record-formats.md` | data-structures | Record layouts with byte offsets and field sizes |
| `data-types.md` | data-structures | PL/I type declarations and their Java equivalents |
| `logic-psam1.md` | business-logic | Business logic and algorithms in PSAM1.pli |
| `logic-psam1lib.md` | business-logic | Functions and procedures in PSAM1LIB.pli |
| `logic-psam2.md` | business-logic | Business logic and algorithms in PSAM2.pli |
| `control-flow.md` | business-logic | Control structures, loops, branching, GOTO handling |
| `file-io.md` | io-operations | File open/close, read/write operations |
| `report-layouts.md` | io-operations | Report formatting, page headers, column layouts |
| `input-formats.md` | io-operations | Input file formats and record structures |
| `error-handling.md` | error-handling | ON conditions, error detection, recovery strategies |
| `dependencies.md` | dependencies | Inter-module and external dependencies |
| `special-considerations.md` | special-considerations | PL/I-specific behaviors needing Java equivalents |
| `picture-formats.md` | special-considerations | PICTURE clause formats and editing rules |
| `string-handling.md` | special-considerations | String operations, SUBSTR, concatenation, padding |

## INDEX.md

Generate as the final step with this frontmatter:

```yaml
---
title: "Translation Documentation Index"
category: "index"
summary: "Navigation index for all PL/I to Java translation documentation"
auto_generated: true
last_updated: "YYYY-MM-DD"
document_count: <number>
---
```

Must contain:
- **Reading Order** — table sorted by priority (1 first)
- **By Category** — documents grouped under category headings
- **By Source File** — documents grouped by PL/I source file
- **Tags Index** — all tags with links to documents

## Documentation Rules

- **Over-document** — the Developer has no PL/I knowledge and no access to source
- Document every variable, function, data type, size, format, and constraint
- Include step-by-step logic flows with edge cases
- Always verify understanding with `custom-pli-mcp` server before documenting
- For type mapping details, see skill: `development/type-mapping`
- For frontmatter navigation patterns, see skill: `development/frontmatter-navigation`
