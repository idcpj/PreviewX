# PreviewX — Observability and Diagnostics

## 1. Goals

Users and developers must understand why a preview failed without exposing sensitive file content.

## 2. Event Model

```json
{
  "event": "preview_completed",
  "requestID": "uuid",
  "provider": "com.previewx.code",
  "durationMs": 42,
  "bytesRead": 8192,
  "status": "success"
}
```

## 3. Logging Levels

- error
- warning
- info
- debug

Debug logging is opt-in.

## 4. Privacy

Never log:
- raw file contents
- secrets
- full paths when unnecessary
- AI prompts by default

Use hashed or redacted identifiers.

## 5. Diagnostics UI

Show:
- file type
- selected provider
- duration
- bytes read
- warnings
- failure reason
- plugin version

## 6. Support Bundle

Optional export:
- app version
- OS version
- provider inventory
- recent diagnostic events
- no file contents

## 7. Acceptance

A user can diagnose "why didn't this file preview?" without sending the file to the developer.
