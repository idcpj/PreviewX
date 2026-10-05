# PreviewX — Testing Strategy

## 1. Test Pyramid

```text
             E2E
           /     \
      Integration  Snapshot
       /      \
   Unit      Security
       \      /
      Parser fixtures
```

## 2. Unit Tests

Test:
- classification
- routing
- parser behavior
- error mapping
- resource budgets
- cancellation

## 3. Fixture Corpus

Repository:

```text
Tests/Fixtures/
├── text/
├── code/
├── json/
├── yaml/
├── logs/
├── archives/
├── binary/
├── malformed/
├── unicode/
└── huge/
```

## 4. Snapshot Testing

Snapshot:
- JSON tree
- archive tree
- code rendering
- error states
- metadata cards

Do not snapshot unstable timestamps or machine-specific values.

## 5. Fuzzing

Fuzz:
- parsers
- archive path handling
- encoding detection
- structured data
- binary metadata

## 6. E2E

The E2E suite should verify:
1. install;
2. extension registration;
3. Finder selection;
4. Spacebar preview;
5. correct provider;
6. graceful fallback.

## 7. Acceptance Gate

No provider is production-ready without:
- unit tests
- malformed fixtures
- security tests
- performance baseline
- E2E coverage
