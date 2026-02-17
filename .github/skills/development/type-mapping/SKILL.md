---
name: type-mapping
description: PL/I to Java 21 data type mapping reference. Use when converting PL/I DECLARE statements to Java fields or parsing fixed-length records.
---

# PL/I to Java Type Mapping

## Character Types

| PL/I | Java | Example |
|------|------|---------|
| `CHAR(n)` | `String` | `private final String custId;` |
| `CHAR(1)` | `char` | `private final char recordType;` |
| `CHAR(n) VARYING` | `String` | Variable-length text |

## Decimal Types (always use BigDecimal for money)

| PL/I | Java | Notes |
|------|------|-------|
| `DEC(p,s)` | `BigDecimal` | Fixed decimal, e.g. DEC(7,2) = 7 digits, 2 decimal |
| `FIXED DEC(p,s)` | `BigDecimal` | Same as DEC |

**DEC(7,2) parsing**: Stored as `"0123456"` → represents `1234.56`

```java
String balanceStr = line.substring(51, 58); // 7 bytes
String formatted = balanceStr.substring(0, 5) + "." + balanceStr.substring(5, 7);
BigDecimal balance = new BigDecimal(formatted);
```

## Integer Types

| PL/I | Java |
|------|------|
| `FIXED BIN(15)` | `short` |
| `FIXED BIN(31)` | `int` |
| `FIXED BIN(63)` | `long` |

## Other Types

| PL/I | Java |
|------|------|
| `BIT(1)` | `boolean` |
| `PIC '9999'` | `int` |
| `PIC '99V99'` | `BigDecimal` (implied decimal) |
| Date `CHAR(8)` | `LocalDate` with `DateTimeFormatter` |

## Critical Rules

- **Always** use `BigDecimal` for monetary values (never `double`/`float`)
- **Always** wrap `parseInt`/`parseLong` in try-catch with sensible defaults
- **Always** validate record length before parsing
- Use `substring(start, start + length)` — end is exclusive
