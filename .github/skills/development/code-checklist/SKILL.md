---
name: code-checklist
description: Critical code requirements checklist derived from actual build failures. Use before committing code or when troubleshooting compilation errors.
---

# Code Requirements Checklist

> **Related skills:** `build/build-validation`, `development/java-patterns`

## Exceptions and Constructors

- **NEVER** throw checked exceptions from constructors calling `super()` — use factory methods or composition
- **ALWAYS** wrap `parseInt`/`parseLong`/`new BigDecimal()` in try-catch with defaults

## Comments and Encoding

- **NEVER** use Unicode box-drawing characters (┌ ─ │) in Javadoc — use ASCII (+, -, |)
- **NEVER** nest `/* */` comments inside Javadoc — use `-` instead

## File Editing

- **ALWAYS** include complete method context when doing string replacements
- **ALWAYS** compile immediately after edits (`mvn clean compile`)
- Count `{` and `}` — they must match after every edit

## Common Error Solutions

| Error | Cause | Fix |
|-------|-------|-----|
| `illegal start of expression` | Missing closing `}` | Count braces, add missing ones |
| `unreported exception IOException` | Checked exception in super() | Use factory method pattern |
| `String index out of range` | Wrong substring indices | Use `substring(start, start+length)` |
| `NumberFormatException` | Invalid numeric string | Wrap in try-catch with default |
| `class, interface, enum expected` | Unicode in comments or corrupted file | Use ASCII only in comments |

## Pre-Commit Sequence

```bash
mvn clean compile     # Must succeed, zero errors
mvn package           # Must create JAR
# If DataGenerator exists:
java -cp target/classes com.ibm.pl1ref.util.DataGenerator
java -cp target/psam-translation-0.1.0.jar com.ibm.pl1ref.Main
```
