import Foundation

/// A small, dependency-free Markdown block parser.
///
/// It converts Markdown source into a flat list of ``MarkdownNode`` values that
/// the UI renders as headings, lists, code blocks, quotes, and paragraphs. The
/// parser is intentionally block-level: inline emphasis and links are preserved
/// verbatim in `text` so the renderer can style them, and code fences are kept
/// intact for syntax highlighting.
public enum MarkdownParser {
    public static func parse(_ source: String, maximumNodes: Int = 5_000) -> [MarkdownNode] {
        var nodes: [MarkdownNode] = []
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var index = 0
        var paragraph: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                nodes.append(MarkdownNode(kind: .paragraph, text: text))
            }
            paragraph = []
        }

        while index < lines.count, nodes.count < maximumNodes {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block.
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushParagraph()
                let fence = String(trimmed.prefix(3))
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                index += 1
                while index < lines.count {
                    let inner = lines[index].trimmingCharacters(in: .whitespaces)
                    if inner.hasPrefix(fence) { break }
                    body.append(lines[index])
                    index += 1
                }
                nodes.append(MarkdownNode(
                    kind: .codeBlock,
                    text: body.joined(separator: "\n"),
                    language: language.isEmpty ? nil : language
                ))
                index += 1
                continue
            }

            // Thematic break.
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                nodes.append(MarkdownNode(kind: .thematicBreak, text: ""))
                index += 1
                continue
            }

            // ATX heading.
            let hashes = trimmed.prefix { $0 == "#" }.count
            if (1...6).contains(hashes), trimmed.dropFirst(hashes).first == " " {
                flushParagraph()
                let text = String(trimmed.dropFirst(hashes)).trimmingCharacters(in: .whitespaces)
                nodes.append(MarkdownNode(kind: .heading, text: text, level: hashes))
                index += 1
                continue
            }

            // Blockquote.
            if trimmed.hasPrefix(">") {
                flushParagraph()
                let text = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                nodes.append(MarkdownNode(kind: .quote, text: text))
                index += 1
                continue
            }

            // GFM Table block
            if trimmed.contains("|") && index + 1 < lines.count {
                let nextTrimmed = lines[index + 1].trimmingCharacters(in: .whitespaces)
                if isTableDelimiter(nextTrimmed) {
                    flushParagraph()
                    var tableGrid: [[String]] = []
                    tableGrid.append(parseTableRow(trimmed))
                    index += 2 // skip header and delimiter
                    while index < lines.count {
                        let rowTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                        guard !rowTrimmed.isEmpty, rowTrimmed.contains("|") else { break }
                        tableGrid.append(parseTableRow(rowTrimmed))
                        index += 1
                    }
                    nodes.append(MarkdownNode(kind: .table, text: "", tableData: tableGrid))
                    continue
                }
            }

            // GFM Task list item
            if let task = taskItem(line) {
                flushParagraph()
                nodes.append(MarkdownNode(kind: .taskItem, text: task.text, level: task.depth, isDone: task.isDone))
                index += 1
                continue
            }

            // Unordered list item.
            if let item = unorderedItem(line) {
                flushParagraph()
                nodes.append(MarkdownNode(kind: .listItem, text: item.text, level: item.depth))
                index += 1
                continue
            }

            // Ordered list item.
            if let item = orderedItem(line) {
                flushParagraph()
                nodes.append(MarkdownNode(kind: .orderedListItem, text: item.text, level: item.depth))
                index += 1
                continue
            }

            // Blank line ends a paragraph.
            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            paragraph.append(trimmed)
            index += 1
        }
        flushParagraph()
        return nodes
    }

    private static func isTableDelimiter(_ line: String) -> Bool {
        guard line.contains("|") && line.contains("-") else { return false }
        let clean = line.filter { $0 != " " && $0 != "\t" && $0 != "|" && $0 != ":" && $0 != "-" }
        return clean.isEmpty
    }

    private static func parseTableRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    private static func taskItem(_ line: String) -> (text: String, depth: Int, isDone: Bool)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let prefixes = ["- [ ] ", "* [ ] ", "+ [ ] ", "- [x] ", "- [X] ", "* [x] ", "* [X] "]
        for prefix in prefixes {
            if trimmed.lowercased().hasPrefix(prefix.lowercased()) {
                let isDone = prefix.contains("x") || prefix.contains("X")
                let text = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                return (text, indentDepth(line), isDone)
            }
        }
        return nil
    }

    private static func indentDepth(_ line: String) -> Int {
        var spaces = 0
        for character in line {
            if character == " " { spaces += 1 }
            else if character == "\t" { spaces += 4 }
            else { break }
        }
        return spaces / 2
    }

    private static func unorderedItem(_ line: String) -> (text: String, depth: Int)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["- ", "* ", "+ "] {
            if trimmed.hasPrefix(marker) {
                return (String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces), indentDepth(line))
            }
        }
        return nil
    }

    private static func orderedItem(_ line: String) -> (text: String, depth: Int)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let rest = trimmed.dropFirst(digits.count)
        guard rest.first == "." || rest.first == ")" else { return nil }
        let text = rest.dropFirst().trimmingCharacters(in: .whitespaces)
        return (text, indentDepth(line))
    }
}
