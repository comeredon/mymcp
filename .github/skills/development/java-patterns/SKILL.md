---
name: java-patterns
description: Proven Java 21 design patterns for PL/I to Java translation. Use when implementing Java classes, I/O wrappers, or data models from PL/I specifications.
---

# Java Implementation Patterns

## Pattern 1: Wrapper Composition for I/O

**NEVER** extend PrintWriter from a constructor that throws IOException.

✅ Use composition with a factory method:

```java
public class PagedReportWriter {
    private PrintWriter writer;

    private PagedReportWriter(PrintWriter writer) {
        this.writer = writer;
    }

    public static PagedReportWriter createFileWriter(String fileName) throws IOException {
        PrintWriter pw = new PrintWriter(new BufferedWriter(new FileWriter(fileName)), true);
        return new PagedReportWriter(pw);
    }

    public void println(String text) { writer.println(text); }
    public void close() { writer.close(); }
}
```

## Pattern 2: Immutable Data Models

Parse once in the constructor, make all fields `final`, provide only getters:

```java
public class CustomerRecord {
    private final char recordType;
    private final String customerId;
    private final BigDecimal accountBalance;

    public CustomerRecord(String line) {
        if (line.length() < 80) throw new IllegalArgumentException("Record must be 80 bytes");
        this.recordType = line.charAt(0);
        this.customerId = line.substring(1, 6).trim();
        this.accountBalance = parseBalance(line.substring(51, 58));
    }
}
```

## Pattern 3: Factory Methods for Complex Objects

Use when class creation involves I/O or multi-step setup:

```java
public static Psam1Processor createFromFiles(String custFile, String tranFile, String reportFile) throws IOException {
    List<CustomerRecord> customers = loadCustomers(custFile);
    PagedReportWriter report = PagedReportWriter.createFileWriter(reportFile);
    return new Psam1Processor(customers, report);
}
```

## Pattern 4: Stateless Utility Classes

```java
public class FormatUtils {
    private FormatUtils() { throw new UnsupportedOperationException("Utility class"); }

    public static String formatBalance(BigDecimal value, int width) {
        return String.format("%" + width + "s", String.format("%,.2f", value));
    }
}
```

## Implementation Order

1. Model classes (CustomerRecord, TransactionRecord)
2. Utility classes (FormatUtils, DataGenerator)
3. I/O wrappers (PagedReportWriter)
4. Processors (Psam2, Psam1)
5. Entry point (Main.java)

Validate with `mvn clean compile` after each class.
