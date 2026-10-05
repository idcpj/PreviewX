# PreviewX — Plugin Marketplace

## 1. Scope

Marketplace is P2. The platform must not depend on a marketplace for core functionality.

## 2. Catalog Entry

```json
{
  "id": "com.example.previewx.graphql",
  "name": "GraphQL Preview",
  "version": "1.2.0",
  "publisher": "Example",
  "supportedTypes": ["public.text"],
  "permissions": [],
  "signature": "..."
}
```

## 3. Trust

Possible trust levels:
- PreviewX verified
- signed publisher
- community
- local/manual

Unverified plugins should receive a clear warning.

## 4. Review

Automated:
- manifest validation
- signature validation
- dependency scan
- fixture tests
- resource limit tests

Manual:
- UX
- security
- licensing

## 5. Removal

Uninstall must remove:
- plugin registration
- binaries
- caches
- metadata

It must not delete user files.
