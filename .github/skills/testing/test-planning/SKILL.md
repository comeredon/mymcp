---
name: test-planning
description: Strategic guide for planning comprehensive test coverage. Use when starting a new testing effort or reviewing test gaps.
---

# Test Planning Strategy

> **Related skills:** `testing/unit-testing`, `testing/integration-testing`, `testing/test-data`, `development/frontmatter-navigation`

## Test Scenario Matrix

| Type | Description | Example |
|------|-------------|---------|
| Happy Path | Normal expected usage | Parse valid 80-byte record |
| Boundary Values | Edge of valid range | Balance = 0.00 and 99999.99 |
| Invalid Input | Outside valid range | Record length ≠ 80 |
| Error Conditions | Exceptions and errors | File not found, null input |
| Integration | Component interactions | Psam1 calls Psam2 |

## Test Pyramid

```
     /\     E2E (3-5 tests)
    /  \    Integration (10-20 tests)
   /    \   Unit (40-60 tests, fast & focused)
```

## Coverage Goals by Component

| Priority | Component | Coverage | Test Types |
|----------|-----------|----------|------------|
| P0 | Business Logic | 90%+ | Unit + Integration |
| P0 | Data Models | 95%+ | Unit |
| P1 | I/O Operations | 80%+ | Integration |
| P2 | Utilities | 70%+ | Unit |

## Planning Checklist

- [ ] List all public methods and classes
- [ ] Identify happy path scenarios
- [ ] List boundary values
- [ ] Plan error scenarios
- [ ] Determine what needs mocks vs real components
- [ ] Estimate test count per component
- [ ] Implement critical tests first
