# PreviewX — CLI and Developer Tools

## 1. CLI

Command:

```bash
previewx preview ./config.yaml
```

Other commands:

```bash
previewx providers list
previewx providers doctor
previewx diagnostics export
previewx validate-plugin ./MyPlugin.pxp
previewx benchmark ./fixtures
```

## 2. Output

Human-readable by default.

Machine-readable:

```bash
previewx preview file.json --format json
```

## 3. CI Integration

CI should support:
- provider validation
- fixture regression
- benchmark thresholds
- manifest validation

## 4. Agent Integration

AI coding agents can use:

```bash
previewx validate-plugin
previewx test-provider
previewx benchmark-provider
```

The commands must have deterministic exit codes.

## 5. Exit Codes

- 0 success
- 1 generic failure
- 2 invalid arguments
- 3 validation failure
- 4 compatibility failure
- 5 security policy failure
