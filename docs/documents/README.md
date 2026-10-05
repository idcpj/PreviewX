# PreviewX Documentation

PreviewX is a macOS developer-oriented Quick Look preview platform.

## Document Map

- `00-Project-Vision.md` — vision, goals, principles
- `01-Product-Requirements.md` — functional and non-functional requirements
- `02-System-Architecture.md` — system decomposition and data flow
- `03-Technical-Architecture.md` — Swift/package/runtime architecture
- `04-Plugin-System.md` — provider/plugin lifecycle
- `05-SDK-Design.md` — SDK contracts
- `06-QuickLook-Extension.md` — macOS Quick Look integration
- `07-Preview-Engine.md` — classification, routing, rendering
- `08-BuiltIn-Providers.md` — first-party provider catalog
- `09-UI-UX.md` — UI behavior
- `10-AI-Architecture.md` — optional AI analysis
- `11-Data-Model.md` — persistence and models
- `12-Security-Model.md` — threat model and controls
- `13-Performance-Architecture.md` — performance strategy
- `14-Testing-Strategy.md` — tests and fixtures
- `15-Observability-Diagnostics.md` — diagnostics
- `16-Settings-Configuration.md` — settings
- `17-Distribution-Updates.md` — packaging/release
- `18-Plugin-Marketplace.md` — future marketplace
- `19-CLI-and-Developer-Tools.md` — developer tooling
- `20-Task-Breakdown.md` — implementation roadmap
- `21-ADR-Architecture-Decisions.md` — decisions
- `22-Plugin-Specification.md` — plugin contract
- `23-FFI-Design.md` — Rust/Swift boundary
- `24-API-Reference.md` — API overview
- `25-AI-Agent-Development-Guide.md` — coding-agent rules
- `26-Release-Engineering.md` — CI/CD
- `27-Reference-Links.md` — external references

## Recommended Implementation Order

1. Read 00–03.
2. Implement 07.
3. Implement 06.
4. Implement 08 providers.
5. Implement 12 and 14 continuously, not at the end.
6. Implement 09.
7. Implement 05 and 22 after the internal provider model stabilizes.
8. Implement 10 only after local preview is production-stable.
9. Implement marketplace functionality last.

## Implemented Project

This repository now contains a working macOS implementation as well as the design documents.

```text
PreviewX.xcodeproj/                 Xcode app + embedded Quick Look extension
Package.swift                       SwiftPM workspace and command-line products
Sources/PreviewXCore/               requests, budgets, routing, diagnostics, settings
Sources/PreviewXProviders/          text, code, structured data, logs, archives, binary metadata
Sources/PreviewXUI/                 shared SwiftUI preview and diagnostics interface
Sources/PreviewXApp/                PreviewX macOS app entry point
Sources/PreviewXQuickLook/          QLPreviewingController adapter
Sources/PreviewXCLI/                previewx command-line tool
Tests/                              unit, security, timeout, and fixture coverage
```

The product is local-first and read-only. Preview requests never execute file contents or start network requests. Remote AI remains disabled; the app exposes only an explicit disabled-state action until an approved provider is configured.

### Included Preview Providers

- Plain text with bounded reads, encoding detection, line numbers, search, and line navigation.
- Data-driven syntax rendering for Swift, Objective-C, C/C++, Rust, Go, Python, JavaScript, TypeScript, Java, Kotlin, shell, SQL, HTML/CSS, Dockerfile, dotenv, and INI.
- JSON, YAML, TOML, XML, CSV/TSV, Markdown, and log representations with raw content preserved.
- ZIP, TAR, GZIP, and TAR.GZ inspection without implicit extraction. ZIP path traversal, TAR symlinks, unsafe paths, oversized entry lists, and extreme compression ratios are visibly flagged.
- SQLite header metadata and a deterministic generic binary fallback.
- Conservative local secret warnings for private keys, cloud keys, bearer tokens, and password-like assignments. Warnings never include matched values and do not alter the raw preview.

### Build And Run

Requirements: macOS 14 or later, Xcode 16 or later, and Swift 6.

```bash
swift test
swift run previewx preview Tests/Fixtures/json/valid.json
swift run previewx providers doctor
swift run PreviewXApp
```

For the complete app bundle with the embedded Quick Look extension:

```bash
xcodebuild -project PreviewX.xcodeproj -scheme PreviewX -configuration Debug \
  -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO build
open .build/xcode/Build/Products/Debug/PreviewX.app
```

The checked-in Xcode target is intentionally configured for unsigned local builds. Before testing Finder's Spacebar workflow on another machine or distributing the app, select an Apple Developer team, enable signing for both targets, and install the resulting app. `QLSupportedContentTypes` and the extension embedding phase are already included.

The CLI supports `preview`, `providers list`, `providers doctor`, `diagnostics export`, `validate-plugin`, and `benchmark`. Run `swift run previewx help` for exact arguments and deterministic exit codes.

### Verification

```bash
make test
make xcode-build
```

See [MVP-Traceability.md](MVP-Traceability.md) for the requirement-to-implementation map and remaining release-only work.

## Important Architectural Correction

PreviewX should not be designed as "a single Quick Look extension that dynamically downloads arbitrary native plugins." Apple's Quick Look extension model requires declared supported content types and is OS-managed. PreviewX therefore uses Quick Look as the system integration boundary and a controlled provider architecture underneath it. citeturn0search0turn0search5
