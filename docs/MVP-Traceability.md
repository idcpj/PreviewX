# PreviewX MVP Traceability

| Requirement | Implementation | Evidence |
|---|---|---|
| FR-001 Quick Look integration | `PreviewXQuickLook` target, `QLPreviewingController`, `QLSupportedContentTypes`, embedded `.appex` phase | `make xcode-build` validates the embedded extension bundle |
| FR-002 classification | `FileClassifier` combines system type, extension, and bounded signatures | Swift unit coverage through runtime routing tests |
| FR-003 deterministic routing | `ProviderRegistry` and stable router tie-breakers | `testDataDrivenSourceLanguageRouting` |
| FR-004 text | `TextProvider`, `TextDecoding`, `SourceTextView` | text and timeout/budget test coverage |
| FR-005 structured data | JSON, YAML, TOML, XML, CSV providers emit tree/table/raw blocks | JSON, malformed JSON, CSV tests |
| FR-006 source code | `LanguageCatalog` is data-driven; `SourceCodeProvider` and SwiftUI syntax renderer use it | source-language routing test |
| FR-007 logs | `LogProvider` detects timestamp/severity and preserves raw content | provider implementation and fixtures |
| FR-008 archives | ZIP central-directory, TAR header, GZIP, and TAR.GZ inspectors; no extraction | archive traversal and policy tests |
| FR-009 failures | typed errors map to unsupported, malformed, permission, budget, timeout, security, and unknown states | timeout, malformed JSON, budget, and policy tests |
| FR-010 AI | `PreviewPolicy.allowRemoteAI` defaults false; no network-capable provider exists | `testDefaultPolicyKeepsRemoteAIDisabled` |
| Security S1-S5 | Read-only file access, request-level budgets, archive path policy, local secret warnings, and no AI network path | archive, budget, secret, and policy tests |

## Release-only work

- Configure a real Apple Developer team, signing, notarization, and a stable distribution bundle ID.
- Install a signed build on clean macOS test machines and automate the Finder Spacebar E2E case.
- Add production parser fuzzing and benchmark baselines on supported hardware.
- Implement optional local/remote AI providers only behind the existing explicit consent and policy boundary.
