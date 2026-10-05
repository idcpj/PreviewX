import Foundation
import PreviewXCore

public struct TextProvider: PreviewProvider {
    public let descriptor = ProviderDescriptor(
        id: "com.previewx.text",
        name: "Text",
        supportedTypes: ["public.text", "public.plain-text"],
        extensions: ["txt", "text"],
        priority: 10,
        capabilities: [.search, .lineNavigation, .raw]
    )

    public init() {}

    public func canPreview(_ request: PreviewRequest) async -> ProviderMatch {
        if let language = LanguageCatalog.definition(for: request.identity.url), language.id != "plaintext" {
            return .noMatch
        }
        let ext = ProviderSupport.fileExtension(request)
        if ["md", "markdown", "mdown"].contains(ext) {
            return .noMatch
        }
        let type = request.classification?.contentTypeIdentifier ?? ""
        if type.contains("markdown") {
            return .noMatch
        }
        if type.contains("plain-text") {
            return .init(confidence: 1_000, specificity: 100, reason: "Exact plain-text type")
        }
        if type.contains("text") || ext == "txt" {
            return .init(confidence: 400, specificity: 50, reason: "Text type")
        }
        if ProviderSupport.isLikelyText(request) {
            return .init(confidence: 100, specificity: 1, reason: "Bounded text-content heuristic")
        }
        return .noMatch
    }

    public func makePreview(_ request: PreviewRequest) async throws -> PreviewDocument {
        let decoded = try await TextDecoding.readPreview(identity: request.identity, budget: request.policy.budget, resourceTracker: request.resourceTracker)
        let limited = ProviderSupport.truncateLines(decoded.content, maximum: request.policy.budget.maxTextLines)
        var warnings = ProviderSupport.textWarnings(decoded: decoded, linesTruncated: limited.wasTruncated)
        warnings.append(contentsOf: ProviderSupport.secretWarnings(content: limited.content, policy: request.policy))
        return PreviewDocument(
            title: request.identity.filename,
            subtitle: "Plain text",
            blocks: [.text(.init(content: limited.content))],
            metadata: ProviderSupport.metadata(request: request, provider: descriptor, encoding: decoded.encodingName),
            capabilities: descriptor.capabilities,
            warnings: warnings
        )
    }
}

public struct SourceCodeProvider: PreviewProvider {
    public let descriptor = ProviderDescriptor(
        id: "com.previewx.code",
        name: "Source Code",
        supportedTypes: ["public.source-code", "public.script"],
        extensions: LanguageCatalog.definitions.flatMap { $0.extensions }.sorted(),
        priority: 30,
        capabilities: [.search, .lineNavigation, .raw, .selection, .aiAnalysis]
    )

    public init() {}

    public func canPreview(_ request: PreviewRequest) async -> ProviderMatch {
        if let language = LanguageCatalog.definition(for: request.identity.url), language.id != "plaintext" && language.id != "json" && language.id != "markdown" {
            return .init(confidence: 700, specificity: 100, reason: "Language mapping for \(language.displayName)")
        }
        let ext = ProviderSupport.fileExtension(request)
        if ["md", "markdown", "mdown"].contains(ext) {
            return .noMatch
        }
        let type = request.classification?.contentTypeIdentifier ?? ""
        if type.contains("markdown") {
            return .noMatch
        }
        if type.contains("source") || type.contains("script") {
            return .init(confidence: 400, specificity: 30, reason: "Generic source type")
        }
        return .noMatch
    }

    public func makePreview(_ request: PreviewRequest) async throws -> PreviewDocument {
        let decoded = try await TextDecoding.readPreview(identity: request.identity, budget: request.policy.budget, resourceTracker: request.resourceTracker)
        let limited = ProviderSupport.truncateLines(decoded.content, maximum: request.policy.budget.maxTextLines)
        let language = LanguageCatalog.definition(for: request.identity.url) ?? .init(
            id: "source",
            displayName: "Source Code",
            extensions: []
        )
        var warnings = ProviderSupport.textWarnings(decoded: decoded, linesTruncated: limited.wasTruncated)
        warnings.append(contentsOf: ProviderSupport.secretWarnings(content: limited.content, policy: request.policy))
        return PreviewDocument(
            title: request.identity.filename,
            subtitle: language.displayName,
            blocks: [.code(.init(content: limited.content, language: language.id))],
            metadata: ProviderSupport.metadata(
                request: request,
                provider: descriptor,
                encoding: decoded.encodingName,
                extra: [MetadataItem("Language", language.displayName)]
            ),
            capabilities: descriptor.capabilities,
            warnings: warnings
        )
    }
}

public struct MarkdownProvider: PreviewProvider {
    public let descriptor = ProviderDescriptor(
        id: "com.previewx.markdown",
        name: "Markdown",
        supportedTypes: ["net.daringfireball.markdown"],
        extensions: ["md", "markdown", "mdown"],
        priority: 70,
        capabilities: [.search, .lineNavigation, .tree, .raw, .selection, .aiAnalysis]
    )

    public init() {}

    public func canPreview(_ request: PreviewRequest) async -> ProviderMatch {
        let ext = ProviderSupport.fileExtension(request)
        if descriptor.extensions.contains(ext) {
            return .init(confidence: 950, specificity: 100, reason: "Markdown extension")
        }
        let type = request.classification?.contentTypeIdentifier ?? ""
        if type == "net.daringfireball.markdown" || type.contains("markdown") {
            return .init(confidence: 900, specificity: 90, reason: "Markdown content type")
        }
        return .noMatch
    }

    public func makePreview(_ request: PreviewRequest) async throws -> PreviewDocument {
        let decoded = try await TextDecoding.readPreview(identity: request.identity, budget: request.policy.budget, resourceTracker: request.resourceTracker)
        let limited = ProviderSupport.truncateLines(decoded.content, maximum: request.policy.budget.maxTextLines)
        let headings = MarkdownOutline.headings(in: limited.content, maximumNodes: request.policy.budget.maxOutputNodes)
        let nodes = MarkdownParser.parse(limited.content, maximumNodes: Int(min(request.policy.budget.maxOutputNodes, UInt64(Int.max))))
        var blocks: [PreviewBlock] = [.markdown(.init(source: limited.content, nodes: nodes))]
        if !headings.isEmpty {
            blocks.insert(.tree(.init(title: "Outline", roots: headings)), at: 0)
        }
        var warnings = ProviderSupport.textWarnings(decoded: decoded, linesTruncated: limited.wasTruncated)
        warnings.append(contentsOf: ProviderSupport.secretWarnings(content: limited.content, policy: request.policy))
        return PreviewDocument(
            title: request.identity.filename,
            subtitle: "Markdown",
            blocks: blocks,
            metadata: ProviderSupport.metadata(request: request, provider: descriptor, encoding: decoded.encodingName),
            capabilities: descriptor.capabilities,
            warnings: warnings
        )
    }
}

public struct LogProvider: PreviewProvider {
    public let descriptor = ProviderDescriptor(
        id: "com.previewx.log",
        name: "Log",
        supportedTypes: ["public.text"],
        extensions: ["log", "out", "trace"],
        priority: 75,
        capabilities: [.search, .lineNavigation, .raw, .selection, .aiAnalysis]
    )

    public init() {}

    public func canPreview(_ request: PreviewRequest) async -> ProviderMatch {
        let ext = ProviderSupport.fileExtension(request)
        if descriptor.extensions.contains(ext) {
            return .init(confidence: 700, specificity: 100, reason: "Log extension")
        }
        if ProviderSupport.isLikelyText(request) && request.identity.filename.lowercased().contains("log") {
            return .init(confidence: 300, specificity: 20, reason: "Log filename heuristic")
        }
        return .noMatch
    }

    public func makePreview(_ request: PreviewRequest) async throws -> PreviewDocument {
        let decoded = try await TextDecoding.readPreview(identity: request.identity, budget: request.policy.budget, resourceTracker: request.resourceTracker)
        let limited = ProviderSupport.truncateLines(decoded.content, maximum: request.policy.budget.maxTextLines)
        let blocks: [PreviewBlock] = [.code(.init(content: limited.content, language: "log"))]
        var warnings = ProviderSupport.textWarnings(decoded: decoded, linesTruncated: limited.wasTruncated)
        warnings.append(contentsOf: ProviderSupport.secretWarnings(content: limited.content, policy: request.policy))
        return PreviewDocument(
            title: request.identity.filename,
            subtitle: "Log",
            blocks: blocks,
            metadata: ProviderSupport.metadata(request: request, provider: descriptor, encoding: decoded.encodingName),
            capabilities: descriptor.capabilities,
            warnings: warnings
        )
    }
}

private enum MarkdownOutline {
    static func headings(in text: String, maximumNodes: UInt64) -> [TreeNode] {
        let entries = text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { index, line -> (Int, String, Int)? in
            let value = line.trimmingCharacters(in: .whitespaces)
            let level = value.prefix { $0 == "#" }.count
            guard (1...6).contains(level), value.dropFirst(level).first == " " else { return nil }
            return (level, String(value.dropFirst(level).trimmingCharacters(in: .whitespaces)), index + 1)
        }
        return nestedOutline(entries, maximumNodes: maximumNodes)
    }

    static func nestedOutline(_ entries: [(Int, String, Int)], maximumNodes: UInt64) -> [TreeNode] {
        var index = 0
        var emitted: UInt64 = 0
        func build(level: Int) -> [TreeNode] {
            var nodes: [TreeNode] = []
            while index < entries.count && emitted < maximumNodes {
                let entry = entries[index]
                if entry.0 < level { break }
                if entry.0 > level {
                    break
                }
                index += 1
                emitted += 1
                let children: [TreeNode]
                if index < entries.count && entries[index].0 > level {
                    children = build(level: entries[index].0)
                } else {
                    children = []
                }
                nodes.append(TreeNode(label: entry.1, value: "Line \(entry.2)", children: children))
            }
            return nodes
        }
        guard let minimum = entries.map(\.0).min() else { return [] }
        return build(level: minimum)
    }
}

private enum LogParser {
    static func events(in text: String, maximumRows: Int) -> [[String]] {
        let timestamp = try? NSRegularExpression(pattern: "^\\s*(\\d{4}-\\d{2}-\\d{2}[T ]\\d{2}:\\d{2}:\\d{2}(?:[.,]\\d+)?(?:Z|[+-]\\d{2}:?\\d{2})?)")
        let level = try? NSRegularExpression(pattern: "\\b(TRACE|DEBUG|INFO|NOTICE|WARN(?:ING)?|ERROR|FATAL|CRITICAL)\\b", options: [.caseInsensitive])
        var rows: [[String]] = []
        for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            guard rows.count < maximumRows else { break }
            let content = String(line)
            let range = NSRange(content.startIndex..., in: content)
            let timestampValue = timestamp.flatMap { expression in
                guard let match = expression.firstMatch(in: content, range: range),
                      let capturedRange = Range(match.range(at: 1), in: content)
                else { return nil }
                return String(content[capturedRange])
            } ?? ""
            let levelValue = level.flatMap { expression in
                guard let match = expression.firstMatch(in: content, range: range),
                      let capturedRange = Range(match.range(at: 1), in: content)
                else { return nil }
                return String(content[capturedRange])
            } ?? ""
            if !timestampValue.isEmpty || !levelValue.isEmpty {
                rows.append(["\(offset + 1)", timestampValue, levelValue.uppercased(), content])
            }
        }
        return rows
    }
}
