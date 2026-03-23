---
name: frontmatter-navigation
description: Navigate PL/I translation documentation using YAML frontmatter metadata for efficient code implementation.
---

# Frontmatter Navigation for Translation Documentation

> **Related skills:** `orchestration/analysis-spec`, `development/implementation-workflow`

## How to Use

All files in `translation/` have YAML frontmatter metadata at the top. Use this to efficiently find the right documentation for your current implementation task.

### Step 1: Read the Index

Start by reading `translation/INDEX.md` — it contains:
- A priority-ordered reading list
- Documents grouped by category
- Documents grouped by PL/I source file
- A searchable tags index

### Step 2: Navigate by Task

| Implementation Task | Read These Categories First | Then Check |
|--------------------|-----------------------------|------------|
| Data model classes | `data-structures` (priority 1-2) | `special-considerations` |
| Business logic | `business-logic`, `data-structures` | `control-flow`, `error-handling` |
| File I/O classes | `io-operations`, `data-structures` | `record-formats`, `input-formats` |
| Report generation | `io-operations` (`report-layouts`) | `picture-formats`, `string-handling` |
| Error handling | `error-handling` | `special-considerations` |
| Full translation | Follow priority order 1→5 | All files |

### Step 3: Use Frontmatter Fields

Each document has these frontmatter fields:

| Field | How to Use It |
|-------|---------------|
| `title` | Quick identification of document content |
| `category` | Filter documents by implementation area |
| `source_files` | Find all docs related to a specific PL/I source file |
| `tags` | Search for specific topics (e.g., "BigDecimal", "record-format") |
| `related_docs` | Follow cross-references to connected information |
| `priority` | Reading order: 1=essential context, 5=edge cases only |
| `summary` | One-line description for quick scanning |

### Step 4: Per-Source-File Navigation

When translating a specific PL/I file, filter docs by `source_files`:

- **PSAM1.pli**: Look for docs with `source_files` containing "PSAM1.pli"
- **PSAM1LIB.pli**: Look for docs with `source_files` containing "PSAM1LIB.pli"
- **PSAM2.pli**: Look for docs with `source_files` containing "PSAM2.pli"

### Example Workflow

1. Read `translation/INDEX.md` for the full map
2. For implementing a data model class:
   - Filter INDEX.md for category `data-structures` with priority 1-2
   - Read all matching docs (byte offsets, field declarations, type mappings)
   - Follow `related_docs` links from frontmatter for cross-references
3. For implementing business logic:
   - Filter INDEX.md for category `business-logic`
   - Read all matching docs in priority order
   - Check `related_docs` for error handling and control flow docs
