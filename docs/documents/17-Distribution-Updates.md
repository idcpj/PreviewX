# PreviewX — Distribution and Updates

## 1. Distribution Options

- signed/notarized direct download
- managed enterprise distribution
- Homebrew Cask later if project packaging supports it
- App Store only if architecture and entitlement constraints permit

## 2. Package

```text
PreviewX.app
└── Contents
    ├── MacOS
    ├── Frameworks
    ├── PlugIns
    │   └── PreviewXQuickLook.appex
    └── Resources
```

## 3. Versioning

App:
`MAJOR.MINOR.PATCH`

Plugin:
same semantic versioning plus compatibility metadata.

## 4. Update Safety

- verify signature
- verify package integrity
- stage update
- preserve settings
- support rollback where practical

## 5. Release Checklist

- build reproducibly
- run tests
- run security suite
- run performance suite
- sign
- notarize
- validate extension
- install on clean machine
- test Finder Spacebar
- publish release notes

## 6. Acceptance

A clean macOS machine can install PreviewX and immediately use Quick Look without manual cache manipulation.
