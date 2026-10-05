# PreviewX — Plugin Specification

## 1. Package

Recommended package extension:

`.pxplugin`

Conceptual structure:

```text
Example.pxplugin/
├── manifest.json
├── Resources/
├── Provider/
├── Tests/
└── Signature/
```

The exact packaging mechanism may change before public release; the manifest contract is the stable center.

## 2. Manifest Schema

```json
{
  "schemaVersion": 1,
  "id": "com.example.previewx.provider",
  "name": "Example Provider",
  "version": "1.0.0",
  "publisher": {
    "name": "Example",
    "website": "https://example.invalid"
  },
  "minimumPreviewXVersion": "1.0.0",
  "supportedTypes": [
    "public.text"
  ],
  "extensions": [
    "example"
  ],
  "capabilities": [
    "text"
  ],
  "permissions": []
}
```

## 3. Naming

IDs must be reverse-DNS style.

No spaces.

## 4. Compatibility

Plugin declares:
- minimum app version
- maximum tested app version
- SDK version

## 5. Permissions

Start with an allow-list:
- `file.read.requested`
- `network.ai`
- `external.process`

`external.process` should be unavailable to marketplace plugins in MVP.

## 6. Provider Contract

```swift
func canPreview(_ request: PXRequest) async -> PXMatch
func preview(_ request: PXRequest) async throws -> PXDocument
```

## 7. Acceptance

A plugin must fail closed when:
- manifest is invalid;
- SDK is incompatible;
- permissions are unsupported;
- signature is invalid where required.
