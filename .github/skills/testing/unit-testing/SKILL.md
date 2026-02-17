---
name: unit-testing
description: JUnit 5 unit testing patterns and setup for Java 21. Use when writing or reviewing unit tests for individual methods and classes.
---

# JUnit 5 Unit Testing

## Maven Setup

```xml
<dependency>
    <groupId>org.junit.jupiter</groupId>
    <artifactId>junit-jupiter</artifactId>
    <version>5.10.1</version>
    <scope>test</scope>
</dependency>
<dependency>
    <groupId>org.assertj</groupId>
    <artifactId>assertj-core</artifactId>
    <version>3.24.2</version>
    <scope>test</scope>
</dependency>
```

## Test Structure: Arrange-Act-Assert

```java
@Test
@DisplayName("Should parse valid 80-byte customer record")
void testParseValidRecord() {
    // Arrange
    String record = buildTestRecord('C', "00001", "Jane Smith", new BigDecimal("1234.56"), 15);
    // Act
    CustomerRecord customer = new CustomerRecord(record);
    // Assert
    assertEquals("00001", customer.getCustomerId());
    assertEquals(new BigDecimal("1234.56"), customer.getAccountBalance());
}
```

## Key Patterns

### Parameterized Tests
```java
@ParameterizedTest
@CsvSource({"0000000, 0.00", "0123456, 1234.56", "9999999, 99999.99"})
void testBalances(String raw, BigDecimal expected) {
    String record = buildTestRecordWithBalance(raw);
    assertEquals(expected, new CustomerRecord(record).getAccountBalance());
}
```

### Exception Testing
```java
@Test
void testRejectShortRecord() {
    assertThrows(IllegalArgumentException.class, () -> new CustomerRecord("Short"));
}
```

### Nested Groups
```java
@Nested @DisplayName("Parsing") class ParsingTests { /* ... */ }
@Nested @DisplayName("Validation") class ValidationTests { /* ... */ }
```

### Multiple Assertions
```java
assertAll("Customer fields",
    () -> assertEquals('C', customer.getRecordType()),
    () -> assertEquals("12345", customer.getCustomerId()),
    () -> assertEquals(new BigDecimal("1234.56"), customer.getAccountBalance())
);
```

## Running Tests

```bash
mvn test                              # All tests
mvn test -Dtest=CustomerRecordTest    # Specific class
mvn test -Dtest=*Test#testMethod      # Specific method
```

## Rules

- Test one thing per test method
- Use `@DisplayName` for descriptive names
- Use `@BeforeEach` for fresh test data
- Never depend on test execution order
