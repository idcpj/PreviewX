# PreviewX — Data Model

## 1. Core Entities

### FileIdentity

```swift
struct FileIdentity {
    let url: URL
    let filename: String
    let size: UInt64
    let modifiedAt: Date?
    let contentType: String?
}
```

### ProviderDescriptor

```swift
struct ProviderDescriptor {
    let id: String
    let version: String
    let supportedTypes: [String]
    let extensions: [String]
    let priority: Int
}
```

### PreviewDiagnostic

```swift
struct PreviewDiagnostic {
    let requestID: UUID
    let providerID: String?
    let phase: Phase
    let durationMs: UInt64
    let bytesRead: UInt64
    let status: Status
    let message: String?
}
```

## 2. Persistence

Use SQLite or a small structured store for:
- provider state
- settings
- diagnostics index
- cache metadata

Do not persist file contents by default.

## 3. Cache

Cache records must be invalidated when:
- file identity changes
- provider version changes
- renderer version changes
- security policy changes

## 4. Migration

Schema versions must be explicit.

```text
v1 -> v2 -> v3
```

Never require destructive migration for a normal application update.
