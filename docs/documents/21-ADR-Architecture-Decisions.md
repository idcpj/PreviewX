# PreviewX — Architecture Decision Records

## ADR-001: Native Swift as the primary implementation language

### Decision

Use Swift for the application, Quick Look extension, public SDK, and UI.

### Rationale

Quick Look and Uniform Type Identifiers are native Apple APIs. Keeping the OS boundary in Swift reduces FFI and packaging complexity.

### Consequence

Rust is optional and should only be introduced for parser components with measurable benefits.

## ADR-002: Quick Look Extension is a thin adapter

### Decision

Keep business logic outside the extension where practical.

### Rationale

The extension is OS-managed and should have minimal lifecycle assumptions.

## ADR-003: Provider model is internal-first

### Decision

Build a first-party provider registry before marketplace support.

### Rationale

The marketplace cannot be allowed to define the architecture.

## ADR-004: No implicit AI

### Decision

AI is never called merely because a preview is opened.

### Rationale

Privacy, latency, cost, and predictability.

## ADR-005: Read-only preview

### Decision

Preview providers never mutate the source file.

### Rationale

Quick Look is an inspection workflow.

## ADR-006: Canonical PreviewDocument

### Decision

Providers emit a renderer-neutral model.

### Rationale

Allows multiple frontends and deterministic testing.

## ADR-007: No arbitrary runtime code loading

### Decision

Do not design the system around downloading arbitrary native code into the Quick Look process.

### Rationale

Security and macOS extension constraints. Third-party providers use controlled installation and integration mechanisms.

## ADR-008: UTType-first routing

### Decision

Use Uniform Type Identifiers as the first classification signal, then extension/signature evidence.

### Rationale

UTType is Apple's system-level type abstraction. citeturn0search4
