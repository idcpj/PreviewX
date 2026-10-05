# PreviewX — API Reference

## 1. Preview Runtime

```swift
protocol PreviewRuntime {
    func preview(_ request: PreviewRequest) async -> PreviewResult
}
```

## 2. Registry

```swift
protocol ProviderRegistry {
    func register(_ provider: any PreviewProvider) throws
    func unregister(id: String) throws
    func providers() -> [ProviderDescriptor]
}
```

## 3. Router

```swift
protocol ProviderRouter {
    func route(
        classification: FileClassification,
        preferences: ProviderPreferences
    ) -> ProviderSelection
}
```

## 4. Result

```swift
enum PreviewResult {
    case success(PreviewDocument)
    case partial(PreviewDocument, warnings: [PreviewWarning])
    case unsupported(UnsupportedReason)
    case failed(PreviewError)
}
```

## 5. Capability

```swift
enum PreviewCapability {
    case search
    case lineNavigation
    case tree
    case raw
    case selection
    case aiAnalysis
}
```

## 6. Stability

Anything under the public SDK namespace is versioned. Internal modules may change without compatibility guarantees.
