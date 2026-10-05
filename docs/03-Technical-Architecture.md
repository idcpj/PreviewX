# PreviewX — Technical Architecture

## 1. Technology Baseline

Recommended implementation:

- Swift 6+ where supported by deployment target
- Swift Package Manager for internal modules
- AppKit/SwiftUI for host UI
- QuickLook / QuickLookUI for preview integration
- UniformTypeIdentifiers for file classification
- Foundation for I/O
- OSLog for diagnostics
- XPC or process isolation where required
- Rust only for selected parser engines where it provides measurable value
- C ABI boundary for non-Swift engines
- Go is not a default dependency; use it only for isolated tooling where justified

Apple's current documentation exposes `QLPreviewingController`, `QLPreviewProvider`, `QLFilePreviewRequest`, and `QLPreviewReply` for custom preview extensions. Supported content types are declared by the extension. citeturn0search0turn0search19

## 2. Package Layout

```text
PreviewX/
├── App/
├── QuickLookExtension/
├── Packages/
│   ├── PreviewCore/
│   ├── PreviewRouting/
│   ├── PreviewModel/
│   ├── PreviewUI/
│   ├── PreviewSecurity/
│   ├── PreviewProviders/
│   ├── PreviewArchive/
│   ├── PreviewText/
│   ├── PreviewStructured/
│   ├── PreviewAI/
│   └── PreviewTestKit/
├── Plugins/
└── Tests/
```

## 3. Core Interfaces

```swift
protocol PreviewProvider {
    var descriptor: ProviderDescriptor { get }
    func canPreview(_ request: PreviewRequest) async -> MatchResult
    func makePreview(_ request: PreviewRequest) async throws -> PreviewDocument
}
```

```swift
struct PreviewRequest {
    let fileURL: URL
    let contentType: UTType?
    let filename: String
    let fileSize: UInt64
    let deadline: ContinuousClock.Instant
    let cancellation: CancellationHandle
    let policy: PreviewPolicy
}
```

## 4. Resource Limits

Every provider receives:

```swift
struct ResourceBudget {
    let maxBytesRead: UInt64
    let maxMemoryBytes: UInt64
    let maxCPUTimeMs: UInt64
    let maxOutputNodes: UInt64
    let maxArchiveEntries: UInt64
}
```

Providers must stop when a budget is exceeded.

## 5. Threading

- UI updates on MainActor.
- Parsing off main thread.
- File reads use async APIs where available.
- No synchronous full-file reads in preview entry points.
- Cancellation propagates through all layers.

## 6. Logging

Use structured logs:

```text
category=preview
provider=code
fileType=public.source-code
duration_ms=42
result=success
bytes_read=8123
```

Never log file contents by default.

## 7. Security Boundary

Treat every file as hostile input.

Never:
- execute scripts
- invoke interpreters based on file extension
- follow untrusted archive symlinks
- overwrite the source file
- load dynamic libraries from the previewed file
- send file contents externally without explicit AI action

## 8. Testing

Every provider requires:
- unit tests
- malformed fixtures
- large-file fixtures
- Unicode fixtures
- cancellation test
- resource limit test
- snapshot/render test
- performance benchmark
