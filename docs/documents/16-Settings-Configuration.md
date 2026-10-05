# PreviewX — Settings and Configuration

## 1. Settings Areas

- General
- Providers
- Appearance
- Performance
- Security
- AI
- Diagnostics
- Updates
- Advanced

## 2. Provider Controls

Each provider:
- enabled/disabled
- version
- supported types
- health
- reset
- diagnostics

## 3. Security Controls

- allow archive inspection
- maximum preview size
- secret redaction
- remote AI permission
- telemetry preference

Defaults must be conservative.

## 4. Configuration Storage

Use standard macOS preferences for simple values and an application data store for structured plugin state.

## 5. Configuration Precedence

```text
built-in default
    < user setting
    < policy
```

There is no arbitrary environment override in production unless documented.

## 6. Acceptance

Settings changes:
- take effect predictably;
- survive restart;
- do not corrupt provider state;
- have reset-to-default behavior.
