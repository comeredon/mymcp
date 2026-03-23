---
name: test-execution
description: Guide for running tests, analyzing results, and measuring code coverage with JaCoCo. Use when executing test suites or setting up CI test stages.
---

# Test Execution and Validation

> **Related skills:** `testing/test-planning`, `build/build-validation`

## Maven Commands

```bash
mvn test                    # Unit tests only
mvn verify                  # Unit + integration tests
mvn test -Dtest=ClassName   # Specific class
mvn test -Dtest=Class#method # Specific method
mvn package -DskipTests     # Build without tests
```

## JaCoCo Coverage Setup

```xml
<plugin>
    <groupId>org.jacoco</groupId>
    <artifactId>jacoco-maven-plugin</artifactId>
    <version>0.8.11</version>
    <executions>
        <execution><goals><goal>prepare-agent</goal></goals></execution>
        <execution>
            <id>report</id><phase>test</phase>
            <goals><goal>report</goal></goals>
        </execution>
    </executions>
</plugin>
```

```bash
mvn clean test jacoco:report   # Generate report at target/site/jacoco/index.html
```

## Coverage Goals

| Component | Minimum |
|-----------|---------|
| Business Logic | 90% |
| Data Models | 95% |
| I/O Operations | 80% |
| Utilities | 70% |

## Analyzing Failures

1. Check `target/surefire-reports/TEST-*.txt` for details
2. Look for `expected:<X> but was:<Y>` in assertion errors
3. Re-run specific test: `mvn test -Dtest=Class#method`

## Common Issues

| Problem | Fix |
|---------|-----|
| "Tests Run: 0" | Class name must end with `Test` |
| NoClassDefFoundError | Missing test dependency in pom.xml |
| Flaky tests | Use `@BeforeEach` to reset state |
