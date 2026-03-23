---
name: integration-testing
description: Integration testing patterns for validating component interactions and file I/O. Use when testing multi-component workflows or file operations.
---

# Integration Testing Patterns

> **Related skills:** `testing/unit-testing`, `testing/test-data`, `testing/test-execution`

## File I/O Tests with @TempDir

```java
@TempDir Path tempDir;

@Test
void testReadCustomerFile() throws IOException {
    Path inputFile = tempDir.resolve("CUSTFILE.txt");
    Files.write(inputFile, List.of(buildCustomerRecord("00001", "John Smith")));

    List<CustomerRecord> customers = FileHelpers.readCustomerFile(inputFile.toString());
    assertEquals(1, customers.size());
    assertEquals("John Smith", customers.get(0).getName());
}
```

## Component Interaction Tests

```java
@Test
void testProcessorGeneratesReport() throws IOException {
    Path custFile = tempDir.resolve("CUSTFILE.txt");
    Path reportFile = tempDir.resolve("REPORT.txt");
    createTestFiles(custFile);

    Psam1 processor = Psam1.createFromFiles(custFile.toString(), reportFile.toString());
    processor.execute();

    String report = Files.readString(reportFile);
    assertAll("Report validation",
        () -> assertTrue(report.contains("CUSTOMER REPORT")),
        () -> assertTrue(report.contains("STATISTICAL SUMMARY"))
    );
}
```

## End-to-End Workflow Tests

Test the complete flow: generate data → process → verify output.

## Maven Configuration

```xml
<!-- Integration tests with failsafe plugin -->
<plugin>
    <artifactId>maven-failsafe-plugin</artifactId>
    <version>3.2.3</version>
    <configuration>
        <includes><include>**/*IntegrationTest.java</include></includes>
    </configuration>
</plugin>
```

```bash
mvn verify   # Runs both unit and integration tests
```

## Naming Convention

- `*IntegrationTest.java` for integration tests
- `*E2ETest.java` for end-to-end tests
