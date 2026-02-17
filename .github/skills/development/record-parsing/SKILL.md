---
name: record-parsing
description: Fixed-length record parsing patterns for mainframe-style data files. Use when implementing parsers for 80-byte records or any fixed-length format.
---

# Fixed-Length Record Parsing

## Rule: Document byte layout BEFORE writing code

```
CustomerRecord (80 bytes):
Field     | Offset | Length | Java Extraction
----------|--------|--------|------------------
RecType   |   0    |   1    | charAt(0)
CustID    |   1    |   5    | substring(1, 6)
Name      |   6    |   17   | substring(6, 23)
Occupation|   23   |   28   | substring(23, 51)
Balance   |   51   |   7    | substring(51, 58)
Orders    |   58   |   4    | substring(58, 62)
Padding   |   62   |   18   | (ignored)
```

## Substring Formula

```
To extract LENGTH bytes at OFFSET: substring(OFFSET, OFFSET + LENGTH)
Verify: End - Start = Length → 58 - 51 = 7 ✓
```

## Implementation Pattern

```java
public CustomerRecord(String line) {
    if (line == null || line.length() < 80)
        throw new IllegalArgumentException("Record must be 80 bytes, got: " + (line == null ? "null" : line.length()));

    this.recordType = line.charAt(0);
    this.customerId = line.substring(1, 6).trim();
    this.name = line.substring(6, 23).trim();
    this.occupation = line.substring(23, 51).trim();
    this.accountBalance = parseBalance(line.substring(51, 58));
    this.ordersYtd = parseOrders(line.substring(58, 62));
}
```

## Numeric Field Parsing

```java
private BigDecimal parseBalance(String s) {
    try {
        return new BigDecimal(s.substring(0, 5) + "." + s.substring(5, 7));
    } catch (NumberFormatException e) { return BigDecimal.ZERO; }
}

private int parseOrders(String s) {
    try { return Integer.parseInt(s.trim()); }
    catch (NumberFormatException e) { return 0; }
}
```

## Common Mistakes

- `substring(51, 57)` gives 6 bytes, not 7 — use `substring(51, 58)`
- Not validating line length before parsing
- Not wrapping numeric parsing in try-catch
