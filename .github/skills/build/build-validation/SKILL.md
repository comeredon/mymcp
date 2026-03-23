---
name: build-validation
description: Build and validation workflow for Java Maven projects. Use before committing code or when troubleshooting build errors.
---

# Build Validation Workflow

> **Related skills:** `development/code-checklist`, `testing/test-execution`

## Complete Validation Sequence

```bash
# 1. Verify environment
java -version    # Must be 21+
mvn -version     # Must be 3.8+

# 2. Clean build
mvn clean compile   # Must succeed with zero errors

# 3. Run tests
mvn test            # All tests must pass

# 4. Package
mvn package         # JAR created in target/

# 5. Generate test data (if DataGenerator exists)
java -cp target/classes com.ibm.pl1ref.util.DataGenerator
# Verify: data/CUSTFILE.txt and data/TRANFILE.txt exist, all records 80 bytes

# 6. Run application
java -cp target/psam-translation-0.1.0.jar com.ibm.pl1ref.Main
# Verify: output/REPORT.txt created with expected content
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `package does not exist` | Check pom.xml dependencies, run `mvn clean compile` |
| `Could not find main class` | Check manifest Main-Class, verify class exists |
| `illegal start of expression` | Missing `}` — count braces |
| Data files not found | Check working directory is project root |

## Pre-Commit Checklist

- [ ] `mvn clean compile` — zero errors
- [ ] `mvn package` — JAR created
- [ ] Data files generated (if applicable)
- [ ] Application runs without exceptions
- [ ] Output files contain expected content
