# PreviewX — Built-in Providers

## 1. Provider Catalog

### P0

- Text
- Source Code
- JSON
- YAML
- TOML
- XML
- CSV
- Markdown
- Logs
- Archive
- Generic Binary Metadata

### P1

- SQLite
- plist
- INI
- dotenv
- Dockerfile
- lockfiles
- Git files
- certificates/keys metadata without exposing secret material
- image metadata
- audio/video metadata

## 2. Text Provider

Features:
- encoding detection
- line numbers
- search
- wrapping
- byte/line status
- truncation warning

Never silently transform the raw text.

## 3. Code Provider

Language detection order:
1. UTType
2. extension
3. filename
4. content heuristics

Syntax highlighting is presentation only. The raw file remains authoritative.

## 4. JSON Provider

Features:
- tree view
- raw view
- path display
- key search
- collapse/expand
- scalar type display

Malformed JSON:
- preserve raw input;
- highlight error location if parser exposes one;
- never discard the remainder.

## 5. YAML Provider

YAML can be complex and potentially ambiguous. The provider must use a hardened parser and must not instantiate arbitrary language objects.

## 6. Archive Provider

Display:
- format
- compressed size
- uncompressed size when available
- entry count
- tree
- per-entry metadata

Security:
- detect path traversal
- do not follow symlinks during extraction
- cap recursion
- cap entries
- cap decompression ratio

## 7. Provider Acceptance

Every provider needs at least:
- 10 valid fixtures
- 10 malformed fixtures
- 3 large fixtures
- Unicode fixture
- performance benchmark
- cancellation test
