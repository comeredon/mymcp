---
name: implementation-workflow
description: Step-by-step orchestration guide for PL/I to Java 21 translation. Use when starting a new translation or planning implementation sequence.
---

# PL/I to Java Implementation Workflow

> **Related skills:** `development/type-mapping`, `development/java-patterns`, `development/code-checklist`, `build/build-validation`

## Prerequisites

- All documentation exists in `translation/` folder (overview, structure, logic, io, error-handling, dependencies, special-considerations)
- Java 21 and Maven installed
- Project structure (pom.xml, src/main/java/) exists

## Phase 0: Requirements Analysis

1. Read all `translation/*.md` files
2. List all data model classes needed
3. Map PL/I types to Java (use `type-mapping` skill)
4. Document byte layouts (use `record-parsing` skill)
5. Ask Analyst Agent about ANY unclear specifications

## Phase 1: Model Classes

Implement in order: CustomerRecord → TransactionRecord → BalanceStatistics → SystemDateTime

- Use `java-patterns` skill (Pattern 2: Immutable models)
- Use `record-parsing` skill for byte offsets
- Validate: `mvn clean compile` after each class

## Phase 2: Utilities

- FormatUtils.java — static formatting methods
- DataGenerator.java — create BEFORE writing parsers (use `data-generation` skill)
- Validate generated data: all records exactly 80 bytes

## Phase 3: I/O Components

- PagedReportWriter.java — use composition pattern (use `java-patterns` skill, Pattern 1)

## Phase 4: Processors

- Psam2.java — statistics calculator
- Psam1.java — main processor orchestrating everything

## Phase 5: Entry Point

- Main.java — demo orchestration
- Validate: `mvn package`, run application, verify output

## Phase 6: Final Validation

```bash
mvn clean compile    # Zero errors
mvn package          # JAR created
java -cp target/classes com.ibm.pl1ref.util.DataGenerator  # Data files created
java -cp target/psam-translation-0.1.0.jar com.ibm.pl1ref.Main                  # Report generated
```

Check output/REPORT.txt contains all expected sections.
