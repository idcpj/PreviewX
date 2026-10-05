import Foundation

public struct ProviderDescriptor: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let version: String
    public let supportedTypes: [String]
    public let extensions: [String]
    public let priority: Int
    public let capabilities: Set<PreviewCapability>
    public let isBuiltIn: Bool

    public init(
        id: String,
        name: String,
        version: String = "1.0.0",
        supportedTypes: [String] = [],
        extensions: [String] = [],
        priority: Int = 0,
        capabilities: Set<PreviewCapability> = [],
        isBuiltIn: Bool = true
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.supportedTypes = supportedTypes
        self.extensions = extensions.map { $0.lowercased() }
        self.priority = priority
        self.capabilities = capabilities
        self.isBuiltIn = isBuiltIn
    }
}

public enum ClassificationEvidenceKind: String, Codable, Sendable {
    case declaredType
    case filenameExtension
    case signature
    case contentHeuristic
    case fallback
}

public struct ClassificationEvidence: Codable, Equatable, Sendable {
    public let kind: ClassificationEvidenceKind
    public let value: String
    public let confidence: Double

    public init(kind: ClassificationEvidenceKind, value: String, confidence: Double) {
        self.kind = kind
        self.value = value
        self.confidence = confidence
    }
}

public struct FileClassification: Codable, Equatable, Sendable {
    public let contentTypeIdentifier: String?
    public let filenameExtension: String?
    public let signatures: Set<String>
    public let confidence: Double
    public let evidence: [ClassificationEvidence]

    public init(
        contentTypeIdentifier: String? = nil,
        filenameExtension: String? = nil,
        signatures: Set<String> = [],
        confidence: Double = 0,
        evidence: [ClassificationEvidence] = []
    ) {
        self.contentTypeIdentifier = contentTypeIdentifier
        self.filenameExtension = filenameExtension?.lowercased()
        self.signatures = signatures
        self.confidence = confidence
        self.evidence = evidence
    }
}

public struct ProviderMatch: Comparable, Equatable, Sendable {
    public let confidence: Int
    public let specificity: Int
    public let reason: String

    public init(confidence: Int, specificity: Int, reason: String) {
        self.confidence = confidence
        self.specificity = specificity
        self.reason = reason
    }

    public static let noMatch = ProviderMatch(confidence: 0, specificity: 0, reason: "No match")

    public static func < (lhs: ProviderMatch, rhs: ProviderMatch) -> Bool {
        (lhs.confidence, lhs.specificity) < (rhs.confidence, rhs.specificity)
    }
}

public protocol PreviewProvider: Sendable {
    var descriptor: ProviderDescriptor { get }
    func canPreview(_ request: PreviewRequest) async -> ProviderMatch
    func makePreview(_ request: PreviewRequest) async throws -> PreviewDocument
}

public actor ProviderRegistry {
    private var registeredProviders: [any PreviewProvider] = []

    public init() {}

    public func register(_ provider: any PreviewProvider) throws {
        guard !registeredProviders.contains(where: { $0.descriptor.id == provider.descriptor.id }) else {
            throw PreviewError(.providerUnavailable, "A provider with ID \(provider.descriptor.id) is already registered.")
        }
        registeredProviders.append(provider)
    }

    public func unregister(id: String) throws {
        let oldCount = registeredProviders.count
        registeredProviders.removeAll { $0.descriptor.id == id }
        guard registeredProviders.count != oldCount else {
            throw PreviewError(.providerUnavailable, "Provider \(id) is not registered.")
        }
    }

    public func providers() -> [any PreviewProvider] {
        registeredProviders
    }

    public func descriptors() -> [ProviderDescriptor] {
        registeredProviders.map(\.descriptor).sorted { $0.id < $1.id }
    }
}

public struct ProviderSelection: Sendable {
    public let provider: any PreviewProvider
    public let match: ProviderMatch

    public init(provider: any PreviewProvider, match: ProviderMatch) {
        self.provider = provider
        self.match = match
    }
}
