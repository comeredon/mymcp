---
name: mocking
description: Mockito mocking patterns for isolating units under test. Use when testing classes with external dependencies like databases, files, or APIs.
---

# Mockito Mocking Patterns

## Setup

```xml
<dependency>
    <groupId>org.mockito</groupId>
    <artifactId>mockito-junit-jupiter</artifactId>
    <version>5.8.0</version>
    <scope>test</scope>
</dependency>
```

```java
@ExtendWith(MockitoExtension.class)
class ServiceTest {
    @Mock private CustomerRepository mockRepo;
    @InjectMocks private CustomerProcessor processor;
}
```

## Stubbing

```java
when(mockRepo.findById("12345")).thenReturn(testCustomer);
when(mockRepo.findById("00000")).thenThrow(new RecordNotFoundException());
```

## Verifying Interactions

```java
verify(mockRepo).findById("12345");
verify(mockRepo, never()).deleteById(anyString());
verify(mockRepo, times(2)).findById(anyString());
```

## Argument Captors

```java
@Captor ArgumentCaptor<String> captor;

verify(mockWriter).println(captor.capture());
assertEquals("expected output", captor.getValue());
```

## When to Mock vs Use Real Objects

| Mock | Real Object |
|------|-------------|
| Database/file I/O | Value objects (CustomerRecord) |
| External APIs | Pure functions |
| Email services | Simple calculations |
| Slow operations | Utility classes |

## Rules

- Never mock the class under test
- Don't over-mock — only mock external dependencies
- Use `@ExtendWith(MockitoExtension.class)` for cleaner code
- For void methods, use `doThrow().when(mock).method()`
