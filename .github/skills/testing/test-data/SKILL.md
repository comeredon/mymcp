---
name: test-data
description: Strategies for creating comprehensive, realistic test data. Use when setting up test fixtures, builders, or parameterized test data.
---

# Test Data Creation

## Pattern 1: Test Data Builder

```java
public class CustomerRecordTestBuilder {
    private String customerId = "12345";
    private String name = "Test Customer";
    private BigDecimal balance = new BigDecimal("1000.00");
    private int orders = 10;

    public static CustomerRecordTestBuilder aCustomer() { return new CustomerRecordTestBuilder(); }
    public CustomerRecordTestBuilder withBalance(String b) { this.balance = new BigDecimal(b); return this; }
    public CustomerRecordTestBuilder withOrders(int o) { this.orders = o; return this; }

    public CustomerRecord build() { return new CustomerRecord(formatRecord()); }
    private String formatRecord() { /* 80-byte formatting */ }
}

// Usage:
CustomerRecord c = CustomerRecordTestBuilder.aCustomer().withBalance("5432.10").build();
```

## Pattern 2: Constants

```java
public class TestDataConstants {
    public static final String VALID_RECORD = "C12345John Doe         Software Engineer           0123456001018                  ";
    public static final BigDecimal MIN_BALANCE = BigDecimal.ZERO;
    public static final BigDecimal MAX_BALANCE = new BigDecimal("99999.99");
}
```

## Pattern 3: Factory Methods

```java
public static CustomerRecord createHighBalanceCustomer() {
    return CustomerRecordTestBuilder.aCustomer().withBalance("99999.99").build();
}
public static List<CustomerRecord> createCustomers(int count) {
    return IntStream.rangeClosed(1, count).mapToObj(i -> createCustomer(i)).toList();
}
```

## Rules

- Use builders for complex objects
- Use constants for boundary values
- Use `@TempDir` for file-based tests
- Never share mutable test data between tests
- Name test data descriptively (not `data1`, `data2`)
