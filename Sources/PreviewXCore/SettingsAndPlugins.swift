import Darwin
import Foundation

public struct ProviderState: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var isHealthy: Bool
    public var lastFailureMessage: String?

    public init(isEnabled: Bool = true, isHealthy: Bool = true, lastFailureMessage: String? = nil) {
        self.isEnabled = isEnabled
        self.isHealthy = isHealthy
        self.lastFailureMessage = lastFailureMessage
    }
}

public struct PreviewXSettings: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var policy: PreviewPolicy
    public var providerStates: [String: ProviderState]
    public var appearance: Appearance
    public var language: Language

    public enum Appearance: String, Codable, CaseIterable, Sendable {
        case system
        case light
        case dark
    }

    public enum Language: String, Codable, CaseIterable, Sendable {
        case system
        case zhHans = "zh-Hans"
        case en

        public var title: String {
            switch self {
            case .system: "跟随系统 / System"
            case .zhHans: "简体中文"
            case .en: "English"
            }
        }

        public var isChinese: Bool {
            switch self {
            case .system:
                let lang = Locale.preferredLanguages.first ?? Locale.current.identifier
                return lang.lowercased().hasPrefix("zh")
            case .zhHans:
                return true
            case .en:
                return false
            }
        }

        public var locale: Locale {
            switch self {
            case .system:
                return Locale.autoupdatingCurrent
            case .zhHans:
                return Locale(identifier: "zh-Hans")
            case .en:
                return Locale(identifier: "en")
            }
        }
    }

    public init(
        schemaVersion: Int = 1,
        policy: PreviewPolicy = .default,
        providerStates: [String: ProviderState] = [:],
        appearance: Appearance = .system,
        language: Language = .system
    ) {
        self.schemaVersion = schemaVersion
        self.policy = policy
        self.providerStates = providerStates
        self.appearance = appearance
        self.language = language
    }

    public init() {
        self.init(
            schemaVersion: 1,
            policy: .default,
            providerStates: [:],
            appearance: .system,
            language: .system
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case policy
        case providerStates
        case appearance
        case language
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        policy = try container.decodeIfPresent(PreviewPolicy.self, forKey: .policy) ?? .default
        providerStates = try container.decodeIfPresent([String: ProviderState].self, forKey: .providerStates) ?? [:]
        appearance = try container.decodeIfPresent(Appearance.self, forKey: .appearance) ?? .system
        language = try container.decodeIfPresent(Language.self, forKey: .language) ?? .system
    }

    public func effectivePolicy() -> PreviewPolicy {
        var effective = policy
        let enabled = Set(providerStates.compactMap { id, state in
            state.isEnabled ? id : nil
        })
        effective.enabledProviderIDs = providerStates.isEmpty ? nil : enabled
        return effective
    }
}

public enum PreviewXPaths {
    public static let appGroupID = "group.com.idcpj.previewx"

    public static func realHomeDirectory() -> URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public static func supportDirectory() -> URL {
        let directory = realHomeDirectory()
            .appendingPathComponent("Library/Application Support/PreviewX", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static func settingsURL() -> URL {
        supportDirectory().appendingPathComponent("settings.json")
    }

    public static func diagnosticsURL() -> URL {
        supportDirectory().appendingPathComponent("diagnostics.json")
    }
}

public actor SettingsStore {
    private let fileURL: URL
    private var cached: PreviewXSettings

    public init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL), let decoded = try? JSONDecoder().decode(PreviewXSettings.self, from: data) {
            cached = decoded
        } else {
            cached = PreviewXSettings()
        }
    }

    public func settings() -> PreviewXSettings { cached }

    public func update(_ settings: PreviewXSettings) throws {
        cached = settings
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    public func reset() throws {
        try update(PreviewXSettings())
    }
}

public struct PluginManifest: Codable, Equatable, Sendable {
    public struct Publisher: Codable, Equatable, Sendable {
        public let name: String
        public let website: String?

        public init(name: String, website: String? = nil) {
            self.name = name
            self.website = website
        }
    }

    public let schemaVersion: Int
    public let id: String
    public let name: String
    public let version: String
    public let minimumPreviewXVersion: String
    public let supportedTypes: [String]
    public let extensions: [String]
    public let capabilities: Set<PreviewCapability>
    public let permissions: Set<String>
    public let publisher: Publisher?

    public init(
        schemaVersion: Int = 1,
        id: String,
        name: String,
        version: String,
        minimumPreviewXVersion: String,
        supportedTypes: [String],
        extensions: [String],
        capabilities: Set<PreviewCapability>,
        permissions: Set<String> = [],
        publisher: Publisher? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.version = version
        self.minimumPreviewXVersion = minimumPreviewXVersion
        self.supportedTypes = supportedTypes
        self.extensions = extensions
        self.capabilities = capabilities
        self.permissions = permissions
        self.publisher = publisher
    }
}

public enum PluginManifestValidator {
    public static let supportedPermissions: Set<String> = ["file.read.requested", "network.ai"]

    public static func validate(_ manifest: PluginManifest) throws {
        guard manifest.schemaVersion == 1 else {
            throw PreviewError(.unsupported, "Plugin manifest schema \(manifest.schemaVersion) is not supported.")
        }
        let pattern = "^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+){2,}$"
        guard manifest.id.range(of: pattern, options: .regularExpression) != nil else {
            throw PreviewError(.malformed, "Plugin ID must use reverse-DNS notation.")
        }
        guard !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PreviewError(.malformed, "Plugin name cannot be empty.")
        }
        guard semanticVersionIsValid(manifest.version), semanticVersionIsValid(manifest.minimumPreviewXVersion) else {
            throw PreviewError(.malformed, "Plugin versions must be semantic versions such as 1.0.0.")
        }
        guard manifest.permissions.isSubset(of: supportedPermissions) else {
            throw PreviewError(.securityPolicyViolation, "Plugin requests an unsupported permission.")
        }
        guard !manifest.supportedTypes.isEmpty || !manifest.extensions.isEmpty else {
            throw PreviewError(.malformed, "Plugin must declare at least one supported type or extension.")
        }
    }

    private static func semanticVersionIsValid(_ value: String) -> Bool {
        value.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+([-.][A-Za-z0-9.]+)?$", options: .regularExpression) != nil
    }
}
