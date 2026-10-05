# PreviewX — Security Model

## 1. Threat Model

Treat previewed content as untrusted.

Threats:
- parser vulnerabilities
- zip bombs
- path traversal
- malicious symlinks
- malformed Unicode
- oversized input
- decompression bombs
- malicious metadata
- prompt injection in files
- data exfiltration through AI

## 2. Security Rules

### Rule S1

Preview never executes content.

### Rule S2

Archive paths are normalized and validated.

### Rule S3

No network access is required for normal preview.

### Rule S4

AI instructions inside a file are data, not authority.

### Rule S5

Remote AI requires explicit user action.

## 3. Archive Safety

Reject or quarantine:
- absolute paths
- `../` traversal
- excessive nesting
- excessive entry counts
- extreme compression ratios

## 4. Secret Detection

Use conservative detectors for:
- API keys
- private key headers
- cloud credentials
- bearer tokens
- password-like assignments

Detection is advisory and must not be treated as perfect.

## 5. Sandboxing

Use macOS sandboxing and the minimum required entitlements. Provider code should not receive broad filesystem access beyond the requested file.

## 6. Incident Handling

If a provider crashes repeatedly:
1. record crash signature;
2. disable provider for session;
3. show diagnostic ID;
4. preserve safe logs;
5. allow user to re-enable.

## 7. Acceptance

Security tests must include adversarial fixtures and regression tests for every fixed vulnerability.
