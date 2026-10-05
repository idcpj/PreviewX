# PreviewX — Product Requirements Document

## 1. Product Scope

PreviewX provides a unified developer-centric Quick Look experience. It must work with Finder's Spacebar workflow and should also expose the same preview engine to the PreviewX application for diagnostics and richer inspection.

Apple documents that Finder can display Quick Look when a user selects a file and presses Spacebar, and custom data types can be supported through Quick Look Preview Extensions. citeturn0search9turn0search0

## 2. Personas

### Developer

Needs immediate inspection of source, config, logs, JSON, SQL, YAML, Docker files, manifests, and generated artifacts.

### SRE / DevOps

Needs fast inspection of logs, deployment manifests, container configs, environment files, archives, and structured output.

### Security Engineer

Needs read-only inspection, archive structure, hashes, metadata, and safe handling of suspicious files.

### Power User

Needs a universal "what is inside this file?" action without opening a heavyweight application.

## 3. Functional Requirements

### FR-001 Quick Look integration

When a supported file is selected in Finder and Space is pressed, PreviewX must provide a preview.

Acceptance:
- The extension is registered for the relevant UTTypes.
- Preview generation completes or fails with a user-visible explanation.
- The Finder remains responsive.

### FR-002 File classification

The runtime must classify using:
1. declared UTType;
2. filename extension;
3. MIME/type tags where available;
4. content sniffing only when safe and bounded.

No provider may rely solely on an extension.

### FR-003 Provider routing

A provider declares:
- provider ID
- supported UTTypes
- filename patterns
- optional content signatures
- priority
- capabilities
- resource requirements

The router must select exactly one primary renderer for a preview request.

### FR-004 Text preview

Support:
- UTF-8
- UTF-16
- common legacy encodings where safely detectable
- line numbering
- syntax highlighting
- large-file viewport loading
- search

### FR-005 Structured data

P0:
- JSON
- YAML
- TOML
- XML
- CSV

Structured rendering must expose both formatted and raw representations when practical.

### FR-006 Source code

Initial languages:
- Swift
- Objective-C
- C/C++
- Rust
- Go
- Python
- JavaScript/TypeScript
- Java/Kotlin
- Shell
- SQL
- HTML/CSS
- Markdown

The language mapping must be data-driven, not hard-coded in the UI.

### FR-007 Logs

The log provider should:
- detect timestamps
- detect severity
- preserve original text
- allow search
- avoid parsing assumptions that alter raw content

### FR-008 Archives

Support archive inspection without executing content.

MVP formats:
- ZIP
- TAR
- GZIP
- 7z if a safe decoder is available
- common compressed tar variants

The first preview should show an archive tree and metadata. Extraction is optional and must never be implicit.

### FR-009 Error handling

Every failure must map to:
- unsupported
- malformed
- permission denied
- too large
- timeout
- memory limit
- provider unavailable
- security policy violation
- unknown

### FR-010 AI

AI is disabled by default for ordinary previewing. A user action must explicitly invoke analysis.

## 4. Non-Functional Requirements

### Performance

- First meaningful content before secondary decoration.
- Progressive rendering.
- No full read for huge files.
- Memory budget per preview.
- Cancellation support.

### Security

- No arbitrary execution.
- No shell invocation from untrusted file content.
- Archive traversal protection.
- Symlink protection.
- Sensitive-file policy.
- Network disabled in the base preview path.

### Reliability

A provider failure must not crash the PreviewX host.

### Privacy

AI requests must disclose:
- provider
- destination
- file scope
- approximate data size
- whether local or remote

## 5. UX States

```text
Loading
  ├─ Preview
  ├─ Partial preview
  ├─ Unsupported
  ├─ Restricted
  └─ Failed
```

Every non-preview state must include an actionable reason.

## 6. Acceptance Test Matrix

| Requirement | Test |
|---|---|
| Spacebar preview | Select fixture in Finder and press Space |
| Large file | 500 MB log fixture |
| Malformed JSON | Invalid nesting fixture |
| Archive traversal | `../` entries |
| Binary | Random binary fixture |
| Permission | unreadable fixture |
| Unicode | CJK + emoji + RTL fixture |
| Encoding | UTF-8/UTF-16 fixtures |
| AI disabled | Confirm zero network requests |

## 7. AI Agent Task Rules

Agents implementing requirements must:
1. read this document;
2. locate the corresponding requirement ID;
3. implement tests first where practical;
4. avoid inventing unsupported Apple APIs;
5. record architecture deviations in ADRs;
6. update the traceability matrix.
