import Foundation

public struct FileIdentity: Codable, Equatable, Sendable {
    public let url: URL
    public let filename: String
    public let size: UInt64
    public let modifiedAt: Date?
    public let contentTypeIdentifier: String?

    public init(
        url: URL,
        filename: String? = nil,
        size: UInt64,
        modifiedAt: Date? = nil,
        contentTypeIdentifier: String? = nil
    ) {
        self.url = url
        self.filename = filename ?? url.lastPathComponent
        self.size = size
        self.modifiedAt = modifiedAt
        self.contentTypeIdentifier = contentTypeIdentifier
    }
}

public struct ResourceBudget: Codable, Equatable, Sendable {
    public var maxBytesRead: UInt64
    public var maxMemoryBytes: UInt64
    public var maxCPUTimeMs: UInt64
    public var maxOutputNodes: UInt64
    public var maxArchiveEntries: UInt64
    public var maxTextLines: UInt64

    public init(
        maxBytesRead: UInt64 = 8 * 1_024 * 1_024,
        maxMemoryBytes: UInt64 = 64 * 1_024 * 1_024,
        maxCPUTimeMs: UInt64 = 2_000,
        maxOutputNodes: UInt64 = 10_000,
        maxArchiveEntries: UInt64 = 10_000,
        maxTextLines: UInt64 = 20_000
    ) {
        self.maxBytesRead = maxBytesRead
        self.maxMemoryBytes = maxMemoryBytes
        self.maxCPUTimeMs = maxCPUTimeMs
        self.maxOutputNodes = maxOutputNodes
        self.maxArchiveEntries = maxArchiveEntries
        self.maxTextLines = maxTextLines
    }

    public static let `default` = ResourceBudget()
    public static let quickLook = ResourceBudget(
        maxBytesRead: 4 * 1_024 * 1_024,
        maxMemoryBytes: 32 * 1_024 * 1_024,
        maxCPUTimeMs: 1_500,
        maxOutputNodes: 5_000,
        maxArchiveEntries: 5_000,
        maxTextLines: 10_000
    )
}

public struct PreviewPolicy: Codable, Equatable, Sendable {
    public var budget: ResourceBudget
    public var allowArchiveInspection: Bool
    public var allowRemoteAI: Bool
    public var redactSecrets: Bool
    public var enabledProviderIDs: Set<String>?
    public var preferredProviderID: String?

    public init(
        budget: ResourceBudget = .default,
        allowArchiveInspection: Bool = true,
        allowRemoteAI: Bool = false,
        redactSecrets: Bool = true,
        enabledProviderIDs: Set<String>? = nil,
        preferredProviderID: String? = nil
    ) {
        self.budget = budget
        self.allowArchiveInspection = allowArchiveInspection
        self.allowRemoteAI = allowRemoteAI
        self.redactSecrets = redactSecrets
        self.enabledProviderIDs = enabledProviderIDs
        self.preferredProviderID = preferredProviderID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        budget = try container.decodeIfPresent(ResourceBudget.self, forKey: .budget) ?? .default
        allowArchiveInspection = try container.decodeIfPresent(Bool.self, forKey: .allowArchiveInspection) ?? true
        allowRemoteAI = try container.decodeIfPresent(Bool.self, forKey: .allowRemoteAI) ?? false
        redactSecrets = try container.decodeIfPresent(Bool.self, forKey: .redactSecrets) ?? true
        enabledProviderIDs = try container.decodeIfPresent(Set<String>.self, forKey: .enabledProviderIDs)
        preferredProviderID = try container.decodeIfPresent(String.self, forKey: .preferredProviderID)
    }

    public static let `default` = PreviewPolicy()
}

public struct PreviewRequest: Sendable {
    public let identity: FileIdentity
    public let classification: FileClassification?
    public let deadline: Date
    public let policy: PreviewPolicy
    public let resourceTracker: PreviewResourceTracker

    public init(
        identity: FileIdentity,
        classification: FileClassification? = nil,
        deadline: Date = Date().addingTimeInterval(2),
        policy: PreviewPolicy = .default,
        resourceTracker: PreviewResourceTracker? = nil
    ) {
        self.identity = identity
        self.classification = classification
        self.deadline = deadline
        self.policy = policy
        self.resourceTracker = resourceTracker ?? PreviewResourceTracker(maxBytesRead: policy.budget.maxBytesRead)
    }

    public var isExpired: Bool { Date() >= deadline }
}

public actor PreviewResourceTracker {
    private let maximumBytes: UInt64
    private var consumedBytes: UInt64 = 0

    public init(maxBytesRead: UInt64) {
        self.maximumBytes = maxBytesRead
    }

    public func reserve(_ bytes: UInt64) throws {
        guard bytes <= maximumBytes, consumedBytes <= maximumBytes - bytes else {
            throw PreviewError(.tooLarge, "The combined reads exceed the preview budget.")
        }
        consumedBytes += bytes
    }

    public func remainingBytes() -> UInt64 {
        maximumBytes - consumedBytes
    }

    public func bytesRead() -> UInt64 {
        consumedBytes
    }
}

public enum PreviewCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case search
    case lineNavigation
    case tree
    case raw
    case selection
    case aiAnalysis
}

public enum PreviewWarningKind: String, Codable, Sendable {
    case truncated
    case malformed
    case security
    case performance
    case unsupportedFeature
    case encoding
}

public struct PreviewWarning: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: PreviewWarningKind
    public let message: String

    public init(kind: PreviewWarningKind, message: String) {
        self.id = UUID()
        self.kind = kind
        self.message = message
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        kind = try container.decode(PreviewWarningKind.self, forKey: .kind)
        message = try container.decode(String.self, forKey: .message)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(message, forKey: .message)
    }
}

public struct MetadataItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String { key }
    public let key: String
    public let value: String

    public init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
    }
}

public struct TextBlock: Codable, Equatable, Sendable {
    public let content: String
    public let lineNumbers: Bool
    public let language: String?

    public init(content: String, lineNumbers: Bool = true, language: String? = nil) {
        self.content = content
        self.lineNumbers = lineNumbers
        self.language = language
    }
}

public struct CodeBlock: Codable, Equatable, Sendable {
    public let content: String
    public let language: String
    public let lineNumbers: Bool

    public init(content: String, language: String, lineNumbers: Bool = true) {
        self.content = content
        self.language = language
        self.lineNumbers = lineNumbers
    }
}

public struct TreeNode: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let label: String
    public let value: String?
    public let detailColumns: [String]?
    public let children: [TreeNode]
    public let isUnsafe: Bool

    public init(
        label: String,
        value: String? = nil,
        detailColumns: [String]? = nil,
        children: [TreeNode] = [],
        isUnsafe: Bool = false
    ) {
        self.id = UUID()
        self.label = label
        self.value = value
        self.detailColumns = detailColumns
        self.children = children
        self.isUnsafe = isUnsafe
    }

    public var optionalChildren: [TreeNode]? {
        children.isEmpty ? nil : children
    }

    private enum CodingKeys: String, CodingKey {
        case label
        case value
        case detailColumns
        case children
        case isUnsafe
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        label = try container.decode(String.self, forKey: .label)
        value = try container.decodeIfPresent(String.self, forKey: .value)
        detailColumns = try container.decodeIfPresent([String].self, forKey: .detailColumns)
        children = try container.decodeIfPresent([TreeNode].self, forKey: .children) ?? []
        isUnsafe = try container.decodeIfPresent(Bool.self, forKey: .isUnsafe) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(label, forKey: .label)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(detailColumns, forKey: .detailColumns)
        try container.encode(children, forKey: .children)
        try container.encode(isUnsafe, forKey: .isUnsafe)
    }
}

public struct TreeBlock: Codable, Equatable, Sendable {
    public let title: String
    public let roots: [TreeNode]
    public let columns: [String]?

    public init(title: String, roots: [TreeNode], columns: [String]? = nil) {
        self.title = title
        self.roots = roots
        self.columns = columns
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case roots
        case columns
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        roots = try container.decode([TreeNode].self, forKey: .roots)
        columns = try container.decodeIfPresent([String].self, forKey: .columns)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(roots, forKey: .roots)
        try container.encodeIfPresent(columns, forKey: .columns)
    }
}

public struct TableBlock: Codable, Equatable, Sendable {
    public let title: String
    public let columns: [String]
    public let rows: [[String]]

    public init(title: String, columns: [String], rows: [[String]]) {
        self.title = title
        self.columns = columns
        self.rows = rows
    }
}

public struct ErrorBlock: Codable, Equatable, Sendable {
    public let title: String
    public let message: String
    public let recoverySuggestion: String?

    public init(title: String, message: String, recoverySuggestion: String? = nil) {
        self.title = title
        self.message = message
        self.recoverySuggestion = recoverySuggestion
    }
}

public struct MarkdownNode: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case heading
        case paragraph
        case listItem
        case orderedListItem
        case taskItem
        case table
        case codeBlock
        case quote
        case thematicBreak
    }

    public var id: UUID
    public let kind: Kind
    public let text: String
    /// Heading level (1-6) or nesting depth for list items.
    public let level: Int
    /// Language hint for `codeBlock` nodes.
    public let language: String?
    /// Completion state for `taskItem` nodes.
    public let isDone: Bool?
    /// Cell matrix for `table` nodes.
    public let tableData: [[String]]?

    public init(
        kind: Kind,
        text: String,
        level: Int = 0,
        language: String? = nil,
        isDone: Bool? = nil,
        tableData: [[String]]? = nil
    ) {
        self.id = UUID()
        self.kind = kind
        self.text = text
        self.level = level
        self.language = language
        self.isDone = isDone
        self.tableData = tableData
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case text
        case level
        case language
        case isDone
        case tableData
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        kind = try container.decode(Kind.self, forKey: .kind)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        level = try container.decodeIfPresent(Int.self, forKey: .level) ?? 0
        language = try container.decodeIfPresent(String.self, forKey: .language)
        isDone = try container.decodeIfPresent(Bool.self, forKey: .isDone)
        tableData = try container.decodeIfPresent([[String]].self, forKey: .tableData)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(text, forKey: .text)
        try container.encode(level, forKey: .level)
        try container.encodeIfPresent(language, forKey: .language)
        try container.encodeIfPresent(isDone, forKey: .isDone)
        try container.encodeIfPresent(tableData, forKey: .tableData)
    }
}

public struct MarkdownBlock: Codable, Equatable, Sendable {
    public let source: String
    public let nodes: [MarkdownNode]

    public init(source: String, nodes: [MarkdownNode]) {
        self.source = source
        self.nodes = nodes
    }
}

public enum PreviewBlock: Codable, Equatable, Sendable {
    case text(TextBlock)
    case code(CodeBlock)
    case tree(TreeBlock)
    case table(TableBlock)
    case error(ErrorBlock)
    case markdown(MarkdownBlock)

    private enum CodingKeys: String, CodingKey {
        case kind
        case text
        case code
        case tree
        case table
        case error
        case markdown
    }

    private enum Kind: String, Codable {
        case text
        case code
        case tree
        case table
        case error
        case markdown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .text:
            self = .text(try container.decode(TextBlock.self, forKey: .text))
        case .code:
            self = .code(try container.decode(CodeBlock.self, forKey: .code))
        case .tree:
            self = .tree(try container.decode(TreeBlock.self, forKey: .tree))
        case .table:
            self = .table(try container.decode(TableBlock.self, forKey: .table))
        case .error:
            self = .error(try container.decode(ErrorBlock.self, forKey: .error))
        case .markdown:
            self = .markdown(try container.decode(MarkdownBlock.self, forKey: .markdown))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(value):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(value, forKey: .text)
        case let .code(value):
            try container.encode(Kind.code, forKey: .kind)
            try container.encode(value, forKey: .code)
        case let .tree(value):
            try container.encode(Kind.tree, forKey: .kind)
            try container.encode(value, forKey: .tree)
        case let .table(value):
            try container.encode(Kind.table, forKey: .kind)
            try container.encode(value, forKey: .table)
        case let .error(value):
            try container.encode(Kind.error, forKey: .kind)
            try container.encode(value, forKey: .error)
        case let .markdown(value):
            try container.encode(Kind.markdown, forKey: .kind)
            try container.encode(value, forKey: .markdown)
        }
    }
}

public struct PreviewDocument: Codable, Equatable, Sendable {
    public let title: String
    public let subtitle: String?
    public let blocks: [PreviewBlock]
    public let metadata: [MetadataItem]
    public let capabilities: Set<PreviewCapability>
    public let warnings: [PreviewWarning]

    public init(
        title: String,
        subtitle: String? = nil,
        blocks: [PreviewBlock],
        metadata: [MetadataItem] = [],
        capabilities: Set<PreviewCapability> = [],
        warnings: [PreviewWarning] = []
    ) {
        self.title = title
        self.subtitle = subtitle
        self.blocks = blocks
        self.metadata = metadata
        self.capabilities = capabilities
        self.warnings = warnings
    }

    /// Presentation blocks for macOS previewing, filtering out redundant outline tree blocks when Markdown is displayed.
    public var presentationBlocks: [PreviewBlock] {
        let hasMarkdown = blocks.contains { if case .markdown = $0 { return true }; return false }
        if hasMarkdown {
            return blocks.filter {
                if case let .tree(tree) = $0, tree.title.localizedCaseInsensitiveContains("outline") {
                    return false
                }
                return true
            }
        }
        return blocks
    }
}

public enum PreviewFailureReason: String, Codable, Sendable {
    case unsupported
    case malformed
    case permissionDenied
    case tooLarge
    case timeout
    case memoryLimit
    case providerUnavailable
    case securityPolicyViolation
    case unknown
}

public struct PreviewError: Error, Codable, Equatable, LocalizedError, Sendable {
    public let reason: PreviewFailureReason
    public let message: String

    public init(_ reason: PreviewFailureReason, _ message: String) {
        self.reason = reason
        self.message = message
    }

    public var errorDescription: String? { message }
}

public enum PreviewResult: Equatable, Sendable {
    case success(PreviewDocument)
    case partial(PreviewDocument, warnings: [PreviewWarning])
    case unsupported(String)
    case failed(PreviewError)
}

public extension PreviewResult {
    var document: PreviewDocument? {
        switch self {
        case let .success(document), let .partial(document, _): document
        case .unsupported, .failed: nil
        }
    }

    var isPartial: Bool {
        if case .partial = self { return true }
        return false
    }
}

public enum ByteFormatHelper {
    public static func format(_ bytes: UInt64) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        }
        let units = ["KB", "MB", "GB", "TB", "PB"]
        var value = Double(bytes) / 1024.0
        var unitIndex = 0
        while value >= 1024.0 && unitIndex < units.count - 1 {
            value /= 1024.0
            unitIndex += 1
        }
        let unit = units[unitIndex]
        if value >= 100 {
            return String(format: "%.0f %@", value, unit)
        } else {
            let str = String(format: "%.1f", value)
            let trimmed = str.hasSuffix(".0") ? String(str.dropLast(2)) : str
            return "\(trimmed) \(unit)"
        }
    }

    public static func format(_ bytes: Int64) -> String {
        guard bytes >= 0 else { return "-" }
        return format(UInt64(bytes))
    }
}
