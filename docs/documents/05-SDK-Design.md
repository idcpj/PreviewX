# PreviewX — SDK Design

## 1. SDK Goals

The SDK lets developers build preview providers without understanding Quick Look internals.

## 2. Public Modules

```text
PreviewXSDK
├── PreviewXCore
├── PreviewXModel
├── PreviewXProvider
├── PreviewXTesting
└── PreviewXSecurity
```

## 3. Provider API

```swift
public protocol PXPreviewProvider {
    static var descriptor: PXProviderDescriptor { get }
    func preview(_ request: PXRequest) async throws -> PXDocument
}
```

## 4. Descriptor

```swift
public struct PXProviderDescriptor: Codable {
    public let id: String
    public let version: String
    public let supportedTypes: [String]
    public let extensions: [String]
    public let priority: Int
    public let capabilities: [PXCapability]
}
```

## 5. Preview Model

```swift
public enum PXBlock {
    case text(PXTextBlock)
    case code(PXCodeBlock)
    case tree(PXTreeBlock)
    case table(PXTableBlock)
    case metadata(PXMetadataBlock)
    case image(PXImageBlock)
    case warning(PXWarningBlock)
}
```

## 6. Security API

The SDK exposes safe file access:

```swift
public protocol PXReadableFile {
    func read(offset: UInt64, length: Int) async throws -> Data
    func stream(offset: UInt64, length: UInt64) -> AsyncThrowingStream<Data, Error>
}
```

No provider receives unrestricted shell execution APIs.

## 7. Testing API

```swift
let result = try await harness.preview(
    fixture: "sample.json",
    provider: "com.previewx.json"
)
XCTAssertEqual(result.status, .success)
```

The SDK includes fixture builders for:
- corrupt data
- large data
- permission errors
- Unicode
- nested archives
- adversarial archive paths

## 8. Versioning

Use semantic versioning:
- major: breaking SDK changes
- minor: additive capabilities
- patch: bug fixes

Provider manifests declare supported SDK ranges.

## 9. Acceptance

An external developer should be able to create a minimal provider using only:
1. SDK package;
2. manifest;
3. provider implementation;
4. tests.
