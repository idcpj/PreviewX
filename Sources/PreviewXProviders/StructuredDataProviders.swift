import Foundation
import CoreFoundation
import PreviewXCore

/// Removes `//` and `/* */` comments, single quotes, trailing commas, and unquoted keys
/// from JSONC and JSON5 input so a standard JSON parser can consume and format it.
enum JSON5Sanitizer {
    static func sanitize(_ input: String) -> String {
        var output = String()
        output.reserveCapacity(input.count)
        let iterator = Array(input)
        var index = 0
        var inString = false
        var stringDelimiter: Character = "\""

        while index < iterator.count {
            let character = iterator[index]
            let next = index + 1 < iterator.count ? iterator[index + 1] : nil

            if inString {
                if character == "\\" && next != nil {
                    // If escaping the delimiter, preserve escape
                    output.append(character)
                    output.append(next!)
                    index += 2
                    continue
                }
                if character == stringDelimiter {
                    inString = false
                    output.append("\"")
                    index += 1
                    continue
                }
                if stringDelimiter == "'" && character == "\"" {
                    // Escape unescaped double quotes inside originally single-quoted strings
                    output.append("\\\"")
                    index += 1
                    continue
                }
                output.append(character)
                index += 1
                continue
            }

            if character == "\"" || character == "'" {
                inString = true
                stringDelimiter = character
                output.append("\"")
                index += 1
                continue
            }

            if character == "/", next == "/" {
                while index < iterator.count, iterator[index] != "\n" { index += 1 }
                continue
            }

            if character == "/", next == "*" {
                index += 2
                while index + 1 < iterator.count, !(iterator[index] == "*" && iterator[index + 1] == "/") {
                    index += 1
                }
                index += 2
                continue
            }

            output.append(character)
            index += 1
        }

        let withoutCommas = removeTrailingCommas(output)
        return quoteUnquotedKeys(withoutCommas)
    }

    private static func removeTrailingCommas(_ input: String) -> String {
        let characters = Array(input)
        var index = 0
        var inString = false
        var result: [Character] = []
        result.reserveCapacity(characters.count)

        while index < characters.count {
            let character = characters[index]
            if inString {
                result.append(character)
                if character == "\\", index + 1 < characters.count {
                    result.append(characters[index + 1])
                    index += 2
                    continue
                }
                if character == "\"" { inString = false }
                index += 1
                continue
            }
            if character == "\"" {
                inString = true
                result.append(character)
                index += 1
                continue
            }
            if character == "," {
                var lookahead = index + 1
                while lookahead < characters.count, characters[lookahead].isWhitespace { lookahead += 1 }
                if lookahead < characters.count, characters[lookahead] == "}" || characters[lookahead] == "]" {
                    index += 1
                    continue
                }
            }
            result.append(character)
            index += 1
        }
        return String(result)
    }

    private static func quoteUnquotedKeys(_ input: String) -> String {
        // Simple regex-based quote repair for unquoted JSON5 keys: { foo: 1 } -> { "foo": 1 }
        let pattern = "([{,]\\s*)([a-zA-Z_$][a-zA-Z0-9_$]*)\\s*:"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let range = NSRange(input.startIndex..., in: input)
        return regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: "$1\"$2\":")
    }
}

public struct JSONProvider: PreviewProvider {
    public let descriptor = ProviderDescriptor(
        id: "com.previewx.json",
        name: "JSON",
        supportedTypes: ["public.json"],
        extensions: ["json", "jsonc", "json5", "geojson", "har", "jsonl", "ndjson"],
        priority: 100,
        capabilities: [.search, .lineNavigation, .raw, .selection, .aiAnalysis]
    )

    public init() {}

    public func canPreview(_ request: PreviewRequest) async -> ProviderMatch {
        let type = request.classification?.contentTypeIdentifier ?? ""
        if type == "public.json" {
            return .init(confidence: 1_000, specificity: 100, reason: "Exact JSON type")
        }
        if descriptor.extensions.contains(ProviderSupport.fileExtension(request)) {
            return .init(confidence: 700, specificity: 100, reason: "JSON extension")
        }
        if ProviderSupport.signatures(request).contains("json-like") {
            return .init(confidence: 800, specificity: 50, reason: "Bounded JSON signature")
        }
        return .noMatch
    }

    public func makePreview(_ request: PreviewRequest) async throws -> PreviewDocument {
        let decoded = try await TextDecoding.readPreview(identity: request.identity, budget: request.policy.budget, resourceTracker: request.resourceTracker)
        let lineLimited = ProviderSupport.truncateLines(decoded.content, maximum: request.policy.budget.maxTextLines)
        var warnings = ProviderSupport.textWarnings(decoded: decoded, linesTruncated: lineLimited.wasTruncated)
        warnings.append(contentsOf: ProviderSupport.secretWarnings(content: lineLimited.content, policy: request.policy))

        let ext = ProviderSupport.fileExtension(request)
        let isJSON5 = ext == "json5"
        let isJSONC = ext == "jsonc"
        let isJSONL = ext == "jsonl" || ext == "ndjson"
        let subtitle = isJSON5 ? "JSON5" : (isJSONC ? "JSONC" : (isJSONL ? "JSON Lines" : "JSON"))

        // Handle empty file safely
        if lineLimited.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return PreviewDocument(
                title: request.identity.filename,
                subtitle: subtitle,
                blocks: [
                    .code(.init(content: lineLimited.content, language: "json"))
                ],
                metadata: ProviderSupport.metadata(request: request, provider: descriptor, encoding: decoded.encodingName),
                capabilities: descriptor.capabilities,
                warnings: warnings
            )
        }

        // Handle JSON Lines
        if isJSONL {
            let lines = lineLimited.content.split(separator: "\n", omittingEmptySubsequences: true)
            var formattedLines: [String] = []
            for line in lines {
                if let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8), options: [.fragmentsAllowed]),
                   let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .fragmentsAllowed]),
                   let str = String(data: data, encoding: .utf8) {
                    formattedLines.append(str)
                } else {
                    formattedLines.append(String(line))
                }
            }
            return PreviewDocument(
                title: request.identity.filename,
                subtitle: "JSON Lines",
                blocks: [
                    .code(.init(content: formattedLines.joined(separator: "\n"), language: "json"))
                ],
                metadata: ProviderSupport.metadata(
                    request: request,
                    provider: descriptor,
                    encoding: decoded.encodingName,
                    extra: [MetadataItem("Records", "\(lines.count)")]
                ),
                capabilities: descriptor.capabilities,
                warnings: warnings
            )
        }

        let parseInput = (isJSONC || isJSON5) ? JSON5Sanitizer.sanitize(lineLimited.content) : decoded.content

        do {
            let object = try JSONSerialization.jsonObject(with: Data(parseInput.utf8), options: [.fragmentsAllowed])
            let prettyData = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
            let formatted = String(data: prettyData, encoding: .utf8) ?? lineLimited.content
            return PreviewDocument(
                title: request.identity.filename,
                subtitle: subtitle,
                blocks: [
                    .code(.init(content: formatted, language: "json"))
                ],
                metadata: ProviderSupport.metadata(request: request, provider: descriptor, encoding: decoded.encodingName),
                capabilities: descriptor.capabilities,
                warnings: warnings
            )
        } catch {
            warnings.append(.init(kind: .malformed, message: "JSON could not be parsed: \(error.localizedDescription)"))
            return PreviewDocument(
                title: request.identity.filename,
                subtitle: "Malformed \(subtitle)",
                blocks: [
                    .error(.init(
                        title: "Unable to parse JSON",
                        message: error.localizedDescription,
                        recoverySuggestion: "Use the raw view to inspect the original content."
                    )),
                    .code(.init(content: lineLimited.content, language: "json"))
                ],
                metadata: ProviderSupport.metadata(request: request, provider: descriptor, encoding: decoded.encodingName),
                capabilities: descriptor.capabilities,
                warnings: warnings
            )
        }
    }
}

public struct YAMLProvider: PreviewProvider {
    public let descriptor = ProviderDescriptor(
        id: "com.previewx.yaml",
        name: "YAML",
        supportedTypes: ["public.yaml"],
        extensions: ["yaml", "yml"],
        priority: 100,
        capabilities: [.search, .lineNavigation, .raw, .selection, .aiAnalysis]
    )

    public init() {}

    public func canPreview(_ request: PreviewRequest) async -> ProviderMatch {
        let type = request.classification?.contentTypeIdentifier ?? ""
        if type.contains("yaml") {
            return .init(confidence: 1_000, specificity: 100, reason: "YAML type")
        }
        if descriptor.extensions.contains(ProviderSupport.fileExtension(request)) {
            return .init(confidence: 700, specificity: 100, reason: "YAML extension")
        }
        return .noMatch
    }

    public func makePreview(_ request: PreviewRequest) async throws -> PreviewDocument {
        let decoded = try await TextDecoding.readPreview(identity: request.identity, budget: request.policy.budget, resourceTracker: request.resourceTracker)
        let limited = ProviderSupport.truncateLines(decoded.content, maximum: request.policy.budget.maxTextLines)
        var warnings = ProviderSupport.textWarnings(decoded: decoded, linesTruncated: limited.wasTruncated)
        warnings.append(contentsOf: ProviderSupport.secretWarnings(content: limited.content, policy: request.policy))
        let outline = IndentedDataOutline.yaml(text: limited.content, maximumNodes: request.policy.budget.maxOutputNodes)
        warnings.append(contentsOf: outline.warnings)
        return PreviewDocument(
            title: request.identity.filename,
            subtitle: "YAML",
            blocks: [
                .code(.init(content: limited.content, language: "yaml"))
            ],
            metadata: ProviderSupport.metadata(request: request, provider: descriptor, encoding: decoded.encodingName),
            capabilities: descriptor.capabilities,
            warnings: warnings
        )
    }
}

public struct TOMLProvider: PreviewProvider {
    public let descriptor = ProviderDescriptor(
        id: "com.previewx.toml",
        name: "TOML",
        supportedTypes: ["net.daringfireball.toml"],
        extensions: ["toml"],
        priority: 100,
        capabilities: [.search, .lineNavigation, .raw, .selection, .aiAnalysis]
    )

    public init() {}

    public func canPreview(_ request: PreviewRequest) async -> ProviderMatch {
        if descriptor.extensions.contains(ProviderSupport.fileExtension(request)) {
            return .init(confidence: 700, specificity: 100, reason: "TOML extension")
        }
        if (request.classification?.contentTypeIdentifier ?? "").contains("toml") {
            return .init(confidence: 1_000, specificity: 100, reason: "TOML type")
        }
        return .noMatch
    }

    public func makePreview(_ request: PreviewRequest) async throws -> PreviewDocument {
        let decoded = try await TextDecoding.readPreview(identity: request.identity, budget: request.policy.budget, resourceTracker: request.resourceTracker)
        let limited = ProviderSupport.truncateLines(decoded.content, maximum: request.policy.budget.maxTextLines)
        var warnings = ProviderSupport.textWarnings(decoded: decoded, linesTruncated: limited.wasTruncated)
        warnings.append(contentsOf: ProviderSupport.secretWarnings(content: limited.content, policy: request.policy))
        let outline = TOMLOutline.parse(text: limited.content, maximumNodes: request.policy.budget.maxOutputNodes)
        warnings.append(contentsOf: outline.warnings)
        return PreviewDocument(
            title: request.identity.filename,
            subtitle: "TOML",
            blocks: [
                .code(.init(content: limited.content, language: "toml"))
            ],
            metadata: ProviderSupport.metadata(request: request, provider: descriptor, encoding: decoded.encodingName),
            capabilities: descriptor.capabilities,
            warnings: warnings
        )
    }
}

public struct XMLProvider: PreviewProvider {
    public let descriptor = ProviderDescriptor(
        id: "com.previewx.xml",
        name: "XML",
        supportedTypes: ["public.xml"],
        extensions: ["xml", "xsd", "svg", "plist"],
        priority: 100,
        capabilities: [.search, .lineNavigation, .raw, .selection, .aiAnalysis]
    )

    public init() {}

    public func canPreview(_ request: PreviewRequest) async -> ProviderMatch {
        let ext = ProviderSupport.fileExtension(request)
        if ["php", "php3", "php4", "php5", "php7", "phtml", "ph3", "ph4", "vue", "svelte", "html", "htm"].contains(ext) {
            return .noMatch
        }
        let type = request.classification?.contentTypeIdentifier ?? ""
        if type == "public.xml" || type.contains("xml") {
            return .init(confidence: 1_000, specificity: 100, reason: "XML type")
        }
        if descriptor.extensions.contains(ProviderSupport.fileExtension(request)) {
            return .init(confidence: 700, specificity: 100, reason: "XML extension")
        }
        if ProviderSupport.signatures(request).contains("xml-like") {
            return .init(confidence: 800, specificity: 50, reason: "Bounded XML signature")
        }
        return .noMatch
    }

    public func makePreview(_ request: PreviewRequest) async throws -> PreviewDocument {
        // 1. Check for macOS binary property list header (bplist00)
        let checkLength = Int(min(8, request.identity.size))
        if checkLength == 8 {
            let header = try? await FileAccess.read(
                request.identity.url,
                length: 8,
                budget: request.policy.budget,
                resourceTracker: request.resourceTracker
            )
            if header == Data("bplist00".utf8) {
                let fullData = try await FileAccess.read(
                    request.identity.url,
                    length: Int(min(request.identity.size, request.policy.budget.maxBytesRead)),
                    budget: request.policy.budget,
                    resourceTracker: request.resourceTracker
                )
                if let plistObj = try? PropertyListSerialization.propertyList(from: fullData, options: [], format: nil),
                   let xmlData = try? PropertyListSerialization.data(fromPropertyList: plistObj, format: .xml, options: 0),
                   let xmlString = String(data: xmlData, encoding: .utf8) {
                    let formatted = Self.prettyPrintedXML(xmlString).content
                    return PreviewDocument(
                        title: request.identity.filename,
                        subtitle: "Binary Property List",
                        blocks: [
                            .code(.init(content: formatted, language: "xml"))
                        ],
                        metadata: ProviderSupport.metadata(
                            request: request,
                            provider: descriptor,
                            encoding: "Binary (bplist00)",
                            extra: [MetadataItem("Converted from", "Apple Binary Plist")]
                        ),
                        capabilities: descriptor.capabilities,
                        warnings: []
                    )
                }
            }
        }

        let decoded = try await TextDecoding.readPreview(identity: request.identity, budget: request.policy.budget, resourceTracker: request.resourceTracker)
        let limited = ProviderSupport.truncateLines(decoded.content, maximum: request.policy.budget.maxTextLines)
        var warnings = ProviderSupport.textWarnings(decoded: decoded, linesTruncated: limited.wasTruncated)
        warnings.append(contentsOf: ProviderSupport.secretWarnings(content: limited.content, policy: request.policy))

        let formattedResult = Self.prettyPrintedXML(limited.content)
        if let malformedError = formattedResult.errorDescription {
            warnings.append(.init(kind: .malformed, message: "XML could not be parsed: \(malformedError)"))
            return PreviewDocument(
                title: request.identity.filename,
                subtitle: "Malformed XML",
                blocks: [
                    .error(.init(
                        title: "Unable to parse XML",
                        message: malformedError,
                        recoverySuggestion: "Use the raw view to inspect the original content."
                    )),
                    .code(.init(content: limited.content, language: "xml"))
                ],
                metadata: ProviderSupport.metadata(request: request, provider: descriptor, encoding: decoded.encodingName),
                capabilities: descriptor.capabilities,
                warnings: warnings
            )
        }

        return PreviewDocument(
            title: request.identity.filename,
            subtitle: "XML",
            blocks: [
                .code(.init(content: formattedResult.content, language: "xml"))
            ],
            metadata: ProviderSupport.metadata(request: request, provider: descriptor, encoding: decoded.encodingName),
            capabilities: descriptor.capabilities,
            warnings: warnings
        )
    }

    private static func prettyPrintedXML(_ raw: String) -> (content: String, errorDescription: String?) {
        guard let doc = try? XMLDocument(xmlString: raw, options: [.nodePreserveWhitespace]) else {
            if let fallbackDoc = try? XMLDocument(xmlString: raw, options: []) {
                let data = fallbackDoc.xmlData(options: [.nodePrettyPrint])
                if let formatted = String(data: data, encoding: .utf8), !formatted.isEmpty {
                    return (formatted, nil)
                }
            }
            let parser = XMLParser(data: Data(raw.utf8))
            _ = parser.parse()
            let err = parser.parserError?.localizedDescription ?? "Invalid XML syntax"
            return (raw, err)
        }
        let data = doc.xmlData(options: [.nodePrettyPrint])
        if let formatted = String(data: data, encoding: .utf8), !formatted.isEmpty {
            return (formatted, nil)
        }
        return (raw, nil)
    }
}

public struct CSVProvider: PreviewProvider {
    public let descriptor = ProviderDescriptor(
        id: "com.previewx.csv",
        name: "CSV",
        supportedTypes: ["public.comma-separated-values-text"],
        extensions: ["csv", "tsv"],
        priority: 100,
        capabilities: [.search, .raw, .selection, .aiAnalysis]
    )

    public init() {}

    public func canPreview(_ request: PreviewRequest) async -> ProviderMatch {
        if descriptor.extensions.contains(ProviderSupport.fileExtension(request)) {
            return .init(confidence: 700, specificity: 100, reason: "Delimited-text extension")
        }
        if (request.classification?.contentTypeIdentifier ?? "").contains("comma-separated") {
            return .init(confidence: 1_000, specificity: 100, reason: "CSV type")
        }
        return .noMatch
    }

    public func makePreview(_ request: PreviewRequest) async throws -> PreviewDocument {
        let decoded = try await TextDecoding.readPreview(identity: request.identity, budget: request.policy.budget, resourceTracker: request.resourceTracker)
        let limited = ProviderSupport.truncateLines(decoded.content, maximum: request.policy.budget.maxTextLines)
        let delimiter: Character = ProviderSupport.fileExtension(request) == "tsv" ? "\t" : ","
        let parsed = DelimitedTextParser.parse(limited.content, delimiter: delimiter, maximumRows: Int(min(request.policy.budget.maxOutputNodes, 1_000)))
        var warnings = ProviderSupport.textWarnings(decoded: decoded, linesTruncated: limited.wasTruncated)
        warnings.append(contentsOf: ProviderSupport.secretWarnings(content: limited.content, policy: request.policy))
        if parsed.unclosedQuote {
            warnings.append(.init(kind: .malformed, message: "The CSV has an unclosed quoted field; rows shown before the error were preserved."))
        }
        if parsed.wasTruncated {
            warnings.append(.init(kind: .truncated, message: "Only the first \(parsed.rows.count.formatted()) rows are shown."))
        }
        let headers = parsed.rows.first ?? []
        let rawRows = Array(parsed.rows.dropFirst())
        let rows = rawRows.filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        var blocks: [PreviewBlock] = []
        if !headers.isEmpty || !rows.isEmpty {
            blocks.append(.table(.init(title: "", columns: headers, rows: rows)))
        } else {
            blocks.append(.code(.init(content: limited.content.isEmpty ? "(Empty file)" : limited.content, language: "csv")))
        }

        return PreviewDocument(
            title: request.identity.filename,
            subtitle: ProviderSupport.fileExtension(request) == "tsv" ? "TSV" : "CSV",
            blocks: blocks,
            metadata: ProviderSupport.metadata(
                request: request,
                provider: descriptor,
                encoding: decoded.encodingName,
                extra: [MetadataItem("Rows", "\(rows.count)")]
            ),
            capabilities: descriptor.capabilities,
            warnings: warnings
        )
    }
}

private struct OutlineResult {
    let roots: [TreeNode]
    let warnings: [PreviewWarning]
}

private enum IndentedDataOutline {
    static func yaml(text: String, maximumNodes: UInt64) -> OutlineResult {
        var entries: [(indent: Int, label: String, value: String?, line: Int)] = []
        var warnings: [PreviewWarning] = []
        for (offset, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(rawLine)
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if line.hasPrefix("\t") {
                warnings.append(.init(kind: .malformed, message: "YAML uses a tab for indentation at line \(offset + 1)."))
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), trimmed != "---", trimmed != "...", !trimmed.hasPrefix("%YAML") else { continue }
            if trimmed.contains("&") || trimmed.contains("*") || trimmed.contains("!") {
                warnings.append(.init(kind: .unsupportedFeature, message: "YAML anchors, aliases, and tags are shown as raw text rather than being resolved."))
            }
            let indent = line.prefix { $0 == " " }.count
            let content = trimmed.hasPrefix("- ") ? String(trimmed.dropFirst(2)) : trimmed
            let isItem = trimmed == "-" || trimmed.hasPrefix("- ")
            let pieces = content.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            if pieces.count == 2 {
                let key = String(pieces[0]).trimmingCharacters(in: .whitespaces)
                let value = String(pieces[1]).trimmingCharacters(in: .whitespaces)
                entries.append((indent, isItem ? "- \(key)" : key, value.isEmpty ? nil : value, offset + 1))
            } else {
                entries.append((indent, isItem ? "- \(content)" : content, nil, offset + 1))
            }
        }
        return OutlineResult(roots: nested(entries: entries, maximumNodes: maximumNodes), warnings: Array(Set(warnings.map(\.message))).map { PreviewWarning(kind: .unsupportedFeature, message: $0) })
    }

    private static func nested(
        entries: [(indent: Int, label: String, value: String?, line: Int)],
        maximumNodes: UInt64
    ) -> [TreeNode] {
        var index = 0
        var emitted: UInt64 = 0
        func build(level: Int) -> [TreeNode] {
            var nodes: [TreeNode] = []
            while index < entries.count && emitted < maximumNodes {
                let entry = entries[index]
                if entry.indent < level { break }
                if entry.indent > level { break }
                index += 1
                emitted += 1
                let childNodes: [TreeNode]
                if index < entries.count, entries[index].indent > level {
                    childNodes = build(level: entries[index].indent)
                } else {
                    childNodes = []
                }
                nodes.append(TreeNode(label: entry.label, value: entry.value ?? "Line \(entry.line)", children: childNodes))
            }
            return nodes
        }
        guard let initial = entries.map(\.indent).min() else { return [] }
        return build(level: initial)
    }
}

private enum TOMLOutline {
    static func parse(text: String, maximumNodes: UInt64) -> OutlineResult {
        var sections: [(name: String, entries: [TreeNode])] = [("Root", [])]
        var warnings: [PreviewWarning] = []
        var count: UInt64 = 0
        for (offset, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            guard count < maximumNodes else {
                warnings.append(.init(kind: .truncated, message: "The TOML tree was limited by the output-node budget."))
                break
            }
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                let name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                sections.append((name.isEmpty ? "Unnamed table" : name, []))
                count += 1
                continue
            }
            let pieces = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count == 2 else {
                warnings.append(.init(kind: .malformed, message: "Unrecognized TOML line \(offset + 1) was preserved in the raw view."))
                continue
            }
            sections[sections.count - 1].entries.append(TreeNode(
                label: String(pieces[0]).trimmingCharacters(in: .whitespaces),
                value: String(pieces[1]).trimmingCharacters(in: .whitespaces)
            ))
            count += 1
        }
        return OutlineResult(
            roots: sections.map { TreeNode(label: $0.name, children: $0.entries) },
            warnings: warnings
        )
    }
}

private final class XMLTreeCollector: NSObject, XMLParserDelegate {
    private final class MutableNode {
        let label: String
        let attributes: [String: String]
        var text = ""
        var children: [MutableNode] = []

        init(label: String, attributes: [String: String]) {
            self.label = label
            self.attributes = attributes
        }
    }

    private let limit: UInt64
    private var count: UInt64 = 0
    private var stack: [MutableNode] = []
    private var rootNodes: [MutableNode] = []
    var didTruncate = false

    init(limit: UInt64) {
        self.limit = limit
    }

    var roots: [TreeNode] { rootNodes.map(freeze) }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard count < limit else {
            didTruncate = true
            parser.abortParsing()
            return
        }
        count += 1
        let node = MutableNode(label: elementName, attributes: attributeDict)
        if let parent = stack.last {
            parent.children.append(node)
        } else {
            rootNodes.append(node)
        }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard let node = stack.last, node.text.count < 240 else { return }
        node.text += String(string.prefix(240 - node.text.count))
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        _ = stack.popLast()
    }

    private func freeze(_ node: MutableNode) -> TreeNode {
        let attributes = node.attributes.keys.sorted().map { "\($0)=\(node.attributes[$0] ?? "")" }.joined(separator: " ")
        let content = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = [attributes, content].filter { !$0.isEmpty }.joined(separator: " ")
        return TreeNode(label: node.label, value: value.isEmpty ? nil : value, children: node.children.map(freeze))
    }
}

private struct DelimitedParseResult {
    let rows: [[String]]
    let unclosedQuote: Bool
    let wasTruncated: Bool
}

private enum DelimitedTextParser {
    static func parse(_ text: String, delimiter: Character, maximumRows: Int) -> DelimitedParseResult {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var iterator = text.makeIterator()
        var pending: Character?
        var wasTruncated = false

        func appendRow() {
            row.append(field)
            field = ""
            if rows.count < maximumRows {
                rows.append(row)
            } else {
                wasTruncated = true
            }
            row = []
        }

        while let character = pending ?? iterator.next() {
            pending = nil
            if character == "\"" {
                if quoted, let next = iterator.next() {
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        quoted = false
                        pending = next
                    }
                } else {
                    quoted.toggle()
                }
            } else if character == delimiter && !quoted {
                row.append(field)
                field = ""
            } else if (character == "\n" || character == "\r") && !quoted {
                if character == "\r", let next = iterator.next(), next != "\n" {
                    pending = next
                }
                appendRow()
            } else {
                field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            appendRow()
        }
        return DelimitedParseResult(rows: rows, unclosedQuote: quoted, wasTruncated: wasTruncated)
    }
}
