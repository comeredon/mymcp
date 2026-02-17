---
name: data-generation
description: Patterns for generating fixed-length test data files. Use BEFORE writing parsers to ensure format consistency between generator and parser.
---

# Data Generation for Fixed-Length Records

## Rule: Generate data BEFORE writing parsers

This prevents format mismatches between generator and parser.

## Record Formatting

```java
public static String formatCustomerRecord(char type, String id, String name,
        String occupation, BigDecimal balance, int orders) {
    StringBuilder record = new StringBuilder(80);
    record.append(type);                                    // 1 byte
    record.append(String.format("%-5s", id));               // 5 bytes
    record.append(String.format("%-17s", name));            // 17 bytes
    record.append(String.format("%-28s", occupation));      // 28 bytes
    record.append(formatBalance(balance, 7));               // 7 bytes
    record.append(String.format("%04d", orders));           // 4 bytes
    while (record.length() < 80) record.append(' ');        // padding
    return record.substring(0, 80);
}
```

## Balance Formatting (BigDecimal → "0123456")

```java
private static String formatBalance(BigDecimal value, int width) {
    BigDecimal scaled = value.multiply(new BigDecimal("100"));
    String str = scaled.setScale(0, RoundingMode.HALF_UP).toString();
    return String.format("%0" + width + "d", Long.parseLong(str));
}
```

## Validation After Generation

```java
private static void validateFile(String filename) throws IOException {
    try (BufferedReader reader = new BufferedReader(new FileReader(filename))) {
        String line; int lineNum = 1;
        while ((line = reader.readLine()) != null) {
            if (line.length() != 80)
                System.err.println("Line " + lineNum + ": expected 80 bytes, got " + line.length());
            lineNum++;
        }
    }
}
```

## Checklist

- [ ] Every record is exactly 80 bytes
- [ ] Balance format matches parser expectations (no decimal point in storage)
- [ ] `data/` directory created if it doesn't exist
- [ ] Test round-trip: generate → parse → verify values match
