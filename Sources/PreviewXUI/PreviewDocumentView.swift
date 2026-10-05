import AppKit
import PreviewXCore
import SwiftUI
import UniformTypeIdentifiers

public struct PreviewResultView: View {
    public let result: PreviewResult
    @Binding public var searchText: String
    @Binding public var requestedLine: Int?

    public init(
        result: PreviewResult,
        searchText: Binding<String>,
        requestedLine: Binding<Int?>
    ) {
        self.result = result
        _searchText = searchText
        _requestedLine = requestedLine
    }

    public var body: some View {
        switch result {
        case let .success(document), let .partial(document, _):
            documentView(document)
        case let .unsupported(reason):
            VStack(spacing: 0) {
                ContentUnavailableView(
                    "Unsupported File",
                    systemImage: "doc.questionmark",
                    description: Text(reason)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                MetadataFooter(items: [], warnings: [])
            }
        case let .failed(error):
            VStack(spacing: 0) {
                ContentUnavailableView(
                    "Unable to Preview",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error.message)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                MetadataFooter(items: [], warnings: [])
            }
        }
    }

    @ViewBuilder
    private func documentView(_ document: PreviewDocument) -> some View {
        VStack(spacing: 0) {
            PreviewBlocksView(
                blocks: document.presentationBlocks,
                searchText: searchText,
                requestedLine: $requestedLine
            )

            Divider()
            MetadataFooter(items: [], warnings: document.warnings)
        }
    }

}

public struct InstantRowButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(configuration.isPressed ? Color.secondary.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
    }
}

public struct TreeSidebarView: View {
    public let documentTitle: String
    public let roots: [TreeNode]
    public let onClose: () -> Void

    @State private var state: TreePresentationState

    public init(
        documentTitle: String,
        roots: [TreeNode],
        onClose: @escaping () -> Void
    ) {
        self.documentTitle = documentTitle
        self.roots = roots
        self.onClose = onClose
        _state = State(initialValue: TreePresentationState(roots: roots))
    }

    public init(
        documentTitle: String,
        state: Binding<TreePresentationState>,
        onClose: @escaping () -> Void
    ) {
        self.documentTitle = documentTitle
        self.roots = state.wrappedValue.roots
        self.onClose = onClose
        _state = State(initialValue: state.wrappedValue)
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("Tree", systemImage: "list.bullet.indent")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Button(action: { state.collapseToDefault() }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Reset to default (root and first-level path only)")

                Button(action: { state.expandAll() }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Expand all nodes")

                Button(action: onClose) {
                    Image(systemName: "sidebar.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Hide tree view")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.06))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(state.visibleNodes) { visibleNode in
                        TreeSidebarRow(
                            visibleNode: visibleNode,
                            isExpanded: state.isExpanded(visibleNode.node.id),
                            onToggle: {
                                state.toggle(visibleNode.node.id)
                            }
                        )
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
            }
        }
    }
}

private struct TreeSidebarRow: View {
    let visibleNode: VisibleTreeNode
    let isExpanded: Bool
    let onToggle: () -> Void
    @State private var isHovered: Bool = false

    private var hasChildren: Bool {
        !visibleNode.node.children.isEmpty
    }

    var body: some View {
        Group {
            if hasChildren {
                Button(action: onToggle) {
                    rowContent
                }
                .buttonStyle(InstantRowButtonStyle())
            } else {
                rowContent
            }
        }
        .onHover { isHovered = $0 }
    }

    private var rowContent: some View {
        HStack(spacing: 4) {
            if visibleNode.depth > 0 {
                Spacer()
                    .frame(width: CGFloat(visibleNode.depth) * 14)
            }

            if hasChildren {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 14, height: 14)
            } else {
                Color.clear
                    .frame(width: 14, height: 14)
            }

            Image(systemName: iconName)
                .font(.system(size: 11))
                .foregroundStyle(iconColor)
                .frame(width: 14)

            Text(visibleNode.node.label)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if let value = visibleNode.node.value {
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if visibleNode.node.isUnsafe {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.red)
                    .font(.caption2)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.secondary.opacity(0.08) : Color.clear)
        )
    }

    private var iconName: String {
        if visibleNode.node.isUnsafe {
            return "exclamationmark.triangle"
        }
        if hasChildren {
            return visibleNode.depth == 0 ? "folder.fill.badge.gearshape" : "folder.fill"
        }
        return "doc.text"
    }

    private var iconColor: Color {
        if visibleNode.node.isUnsafe {
            return .red
        }
        if hasChildren {
            return visibleNode.depth == 0 ? .accentColor : .blue
        }
        return .secondary
    }
}

private struct PreviewBlocksView: View {
    let blocks: [PreviewBlock]
    let searchText: String
    @Binding var requestedLine: Int?

    private var effectiveBlocks: [PreviewBlock] {
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

    private var allTableBlocks: [TableBlock]? {
        guard !effectiveBlocks.isEmpty else { return nil }
        var tables: [TableBlock] = []
        for block in effectiveBlocks {
            if case let .table(table) = block {
                tables.append(table)
            } else {
                return nil
            }
        }
        if tables.count > 1 || (tables.count == 1 && tables[0].title.hasPrefix("Table:")) {
            return tables
        }
        return nil
    }

    private var singleTreeBlock: TreeBlock? {
        guard effectiveBlocks.count == 1, case let .tree(tree) = effectiveBlocks[0] else { return nil }
        return tree
    }

    var body: some View {
        if let tables = allTableBlocks {
            MultiTableMasterDetailView(tables: tables, searchText: searchText)
        } else if let tree = singleTreeBlock {
            ArchiveDetailCardView(block: tree, searchText: searchText)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if effectiveBlocks.isEmpty {
                        ContentUnavailableView("No Content", systemImage: "doc")
                    }
                    ForEach(Array(effectiveBlocks.enumerated()), id: \.offset) { _, block in
                        switch block {
                        case let .text(text):
                            SourceTextView(
                                content: text.content,
                                language: text.language,
                                lineNumbers: text.lineNumbers,
                                searchText: searchText,
                                requestedLine: $requestedLine
                            )
                        case let .code(code):
                            SourceTextView(
                                content: code.content,
                                language: code.language,
                                lineNumbers: code.lineNumbers,
                                searchText: searchText,
                                requestedLine: $requestedLine
                            )
                        case let .tree(tree):
                            TreeBlockView(block: tree, searchText: searchText)
                        case let .table(table):
                            TableBlockView(block: table, searchText: searchText)
                        case let .error(error):
                            ErrorBlockView(block: error)
                        case let .markdown(markdown):
                            MarkdownBlockView(
                                block: markdown,
                                searchText: searchText,
                                requestedLine: $requestedLine
                            )
                        }
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct MultiTableMasterDetailView: View {
    let tables: [TableBlock]
    let searchText: String

    @State private var selectedIndex: Int = 0
    @State private var filterQuery: String = ""

    private var parsedItems: [(index: Int, table: TableBlock, name: String, badge: String)] {
        tables.enumerated().map { index, table in
            let parsed = parseTableMeta(table)
            return (index, table, parsed.name, parsed.badge)
        }
    }

    private var filteredItems: [(index: Int, table: TableBlock, name: String, badge: String)] {
        guard !filterQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            return parsedItems
        }
        return parsedItems.filter { $0.name.localizedCaseInsensitiveContains(filterQuery) }
    }

    private var selectedTable: TableBlock {
        if selectedIndex >= 0 && selectedIndex < tables.count {
            return tables[selectedIndex]
        }
        return tables[0]
    }

    var body: some View {
        HStack(spacing: 0) {
            // 左侧表列表导航
            VStack(alignment: .leading, spacing: 0) {
                // 顶部标题与表数量
                HStack(spacing: 6) {
                    Image(systemName: "cylinder.split.1x2.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.accentColor)
                    Text("Tables")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Text("\(tables.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                if tables.count > 5 {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        TextField("Filter tables...", text: $filterQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                        if !filterQuery.isEmpty {
                            Button(action: { filterQuery = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }

                Divider()

                // 表名列表
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredItems, id: \.index) { item in
                            Button(action: {
                                selectedIndex = item.index
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "tablecells")
                                        .font(.system(size: 11))
                                        .foregroundStyle(selectedIndex == item.index ? Color.accentColor : .secondary)

                                    Text(item.name)
                                        .font(.system(size: 12, weight: selectedIndex == item.index ? .semibold : .regular))
                                        .foregroundStyle(selectedIndex == item.index ? .primary : .secondary)
                                        .lineLimit(1)

                                    Spacer(minLength: 4)

                                    if !item.badge.isEmpty {
                                        Text(item.badge)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(selectedIndex == item.index ? Color.accentColor : .secondary.opacity(0.8))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1.5)
                                            .background(
                                                Capsule()
                                                    .fill(selectedIndex == item.index ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05))
                                            )
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedIndex == item.index ? Color.accentColor.opacity(0.15) : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(InstantRowButtonStyle())
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                }
            }
            .frame(width: 200)
            .background(.ultraThinMaterial)

            Divider()

            // 右侧详情视图
            VStack(alignment: .leading, spacing: 0) {
                TableDetailCardView(table: selectedTable, searchText: searchText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.thinMaterial)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func parseTableMeta(_ table: TableBlock) -> (name: String, badge: String) {
        var cleanTitle = table.title
        if cleanTitle.hasPrefix("Table: ") {
            cleanTitle = String(cleanTitle.dropFirst(7))
        }
        if let parenOpen = cleanTitle.firstIndex(of: "("),
           let parenClose = cleanTitle.lastIndex(of: ")"),
           parenOpen < parenClose {
            let name = String(cleanTitle[..<parenOpen]).trimmingCharacters(in: .whitespaces)
            let inside = String(cleanTitle[cleanTitle.index(after: parenOpen)..<parenClose]).trimmingCharacters(in: .whitespaces)
            let badge: String
            if inside.contains(" of ") {
                let parts = inside.components(separatedBy: " of ")
                if parts.count == 2 {
                    let totalPart = parts[1].replacingOccurrences(of: " rows", with: "").replacingOccurrences(of: " row", with: "").trimmingCharacters(in: .whitespaces)
                    badge = formatNumber(totalPart)
                } else {
                    badge = inside
                }
            } else {
                let numPart = inside.replacingOccurrences(of: " rows", with: "").replacingOccurrences(of: " row", with: "").trimmingCharacters(in: .whitespaces)
                badge = formatNumber(numPart)
            }
            return (name, badge)
        }
        return (cleanTitle, "\(table.rows.count)")
    }

    private func formatNumber(_ text: String) -> String {
        if let num = Int(text.replacingOccurrences(of: ",", with: "")) {
            if num >= 1_000_000 {
                return String(format: "%.1fM", Double(num) / 1_000_000.0)
            } else if num >= 1_000 {
                return String(format: "%.1fk", Double(num) / 1_000.0)
            } else {
                return "\(num)"
            }
        }
        return text
    }
}

private struct TableDetailCardView: View {
    let table: TableBlock
    let searchText: String

    private var filteredRows: [[String]] {
        guard !searchText.isEmpty else { return table.rows }
        return table.rows.filter { $0.joined(separator: " ").localizedCaseInsensitiveContains(searchText) }
    }

    private func columnWidth(at index: Int) -> CGFloat {
        var maxChars = index < table.columns.count ? table.columns[index].count : 4
        for row in filteredRows.prefix(30) {
            if index < row.count {
                maxChars = max(maxChars, row[index].count)
            }
        }
        let calculated = CGFloat(maxChars) * 8.5 + 24
        return max(80, min(320, calculated))
    }

    private var parsedHeader: (tableName: String, subtitle: String) {
        var cleanTitle = table.title
        if cleanTitle.hasPrefix("Table: ") {
            cleanTitle = String(cleanTitle.dropFirst(7))
        }
        if let parenOpen = cleanTitle.firstIndex(of: "("),
           let parenClose = cleanTitle.lastIndex(of: ")"),
           parenOpen < parenClose {
            let name = String(cleanTitle[..<parenOpen]).trimmingCharacters(in: .whitespaces)
            let inside = String(cleanTitle[cleanTitle.index(after: parenOpen)..<parenClose]).trimmingCharacters(in: .whitespaces)
            return (name, "\(inside) · \(table.columns.count) columns")
        }
        return (cleanTitle, "\(table.rows.count) rows · \(table.columns.count) columns")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部 Header 状态信息
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(parsedHeader.tableName)
                        .font(.system(size: 15, weight: .bold))
                    Text(parsedHeader.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if !searchText.isEmpty {
                    Text("\(filteredRows.count) of \(table.rows.count) matching")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // 表格主体数据网格（使用分层单向 ScrollView，避免二维 ScrollView 触发画布居中）
            ScrollView(.vertical) {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // 表头行
                        HStack(spacing: 0) {
                            ForEach(Array(table.columns.enumerated()), id: \.offset) { offset, column in
                                Text(column)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: columnWidth(at: offset), alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                if offset < table.columns.count - 1 {
                                    Divider().frame(height: 16)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .background(Color.primary.opacity(0.04))

                        Divider()

                        // 数据行
                        ForEach(Array(filteredRows.enumerated()), id: \.offset) { rowIndex, row in
                            HStack(spacing: 0) {
                                ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cellValue in
                                    Text(cellValue)
                                        .font(.system(size: 12, design: .monospaced))
                                        .textSelection(.enabled)
                                        .lineLimit(2)
                                        .frame(minWidth: columnWidth(at: colIndex), alignment: .leading)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                    if colIndex < row.count - 1 {
                                        Divider().frame(height: 14).opacity(0.3)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .background(rowIndex % 2 == 1 ? Color.primary.opacity(0.02) : Color.clear)
                            Divider().opacity(0.5)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SourceTextView: View {
    let content: String
    let language: String?
    let lineNumbers: Bool
    let searchText: String
    @Binding var requestedLine: Int?

    private var lines: [String] {
        content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private func rowBackground(for line: String) -> Color {
        let lang = (language ?? "").lowercased()
        if lang == "diff" || lang == "patch" {
            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                return Color.green.opacity(0.12)
            }
            if line.hasPrefix("-") && !line.hasPrefix("---") {
                return Color.red.opacity(0.12)
            }
            if line.hasPrefix("@@") {
                return Color.purple.opacity(0.08)
            }
        }
        return .clear
    }

    var body: some View {
        ScrollViewReader { proxy in
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { offset, line in
                    if searchText.isEmpty || line.localizedCaseInsensitiveContains(searchText) {
                        HStack(alignment: .top, spacing: 12) {
                            if lineNumbers {
                                Text("\(offset + 1)")
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 48, alignment: .trailing)
                            }
                            SyntaxText(line: line, language: language)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .id(offset + 1)
                        .padding(.vertical, 1)
                        .padding(.horizontal, 4)
                        .background(rowBackground(for: line), in: RoundedRectangle(cornerRadius: 2))
                    }
                }
            }
            .onChange(of: requestedLine) { _, line in
                guard let line else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(line, anchor: .center)
                }
            }
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(.separator, lineWidth: 1)
        }
    }
}

private struct SyntaxText: View {
    let line: String
    let language: String?

    var body: some View {
        highlighted
    }

    private var highlighted: Text {
        let tokens = SyntaxHighlighter.tokens(in: line, language: language)
        return tokens.reduce(Text("")) { output, token in
            output + Text(token.text).foregroundColor(color(for: token.kind))
        }
    }

    private func color(for kind: SyntaxTokenKind) -> Color {
        switch kind {
        case .keyword: return .purple
        case .type: return .teal
        case .string: return .green
        case .number: return .orange
        case .comment: return .secondary
        case .function: return .blue
        case .attribute: return .pink
        case .punctuation: return .primary.opacity(0.7)
        case .plain: return .primary
        }
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let searchText: String
    @Binding var requestedLine: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(block.nodes) { node in
                nodeView(node)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1) }
    }

    @ViewBuilder
    private func nodeView(_ node: MarkdownNode) -> some View {
        switch node.kind {
        case .heading:
            VStack(alignment: .leading, spacing: 6) {
                inlineText(node.text)
                    .font(headingFont(level: node.level))
                    .foregroundStyle(.primary)
                    .padding(.top, node.level <= 2 ? 8 : 4)

                if node.level <= 2 {
                    Divider()
                        .opacity(node.level == 1 ? 0.7 : 0.4)
                }
            }

        case .paragraph:
            inlineText(node.text)
                .font(.system(.body, design: .default))
                .lineSpacing(4)
                .textSelection(.enabled)

        case .taskItem:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if node.isDone == true {
                    Image(systemName: "checkmark.square.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.system(size: 14, weight: .semibold))
                } else {
                    Image(systemName: "square")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                }
                inlineText(node.text)
                    .foregroundStyle(node.isDone == true ? Color.primary.opacity(0.85) : Color.primary)
                    .font(.system(.body, design: .default))
            }
            .padding(.leading, CGFloat(node.level) * 16)
            .padding(.vertical, 1)

        case .listItem:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                inlineText(node.text)
                    .font(.system(.body, design: .default))
            }
            .padding(.leading, CGFloat(node.level) * 16)
            .padding(.vertical, 1)

        case .orderedListItem:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(node.level + 1).")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                inlineText(node.text)
                    .font(.system(.body, design: .default))
            }
            .padding(.leading, CGFloat(node.level) * 16)
            .padding(.vertical, 1)

        case .table:
            if let grid = node.tableData, !grid.isEmpty {
                MarkdownTableView(grid: grid)
            }

        case .quote:
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.8))
                    .frame(width: 4)

                inlineText(node.text)
                    .font(.system(.body, design: .default))
                    .foregroundStyle(.secondary)
                    .italic()
                    .lineSpacing(3)
                    .padding(.vertical, 6)
            }
            .padding(.horizontal, 10)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            .fixedSize(horizontal: false, vertical: true)

        case .codeBlock:
            VStack(alignment: .leading, spacing: 0) {
                if let lang = node.language, !lang.isEmpty {
                    HStack {
                        Spacer()
                        Text(lang.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                }

                SourceTextView(
                    content: node.text,
                    language: node.language,
                    lineNumbers: true,
                    searchText: searchText,
                    requestedLine: $requestedLine
                )
            }
            .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.12), lineWidth: 1) }

        case .thematicBreak:
            Divider()
                .padding(.vertical, 4)
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .system(size: 24, weight: .bold)
        case 2: return .system(size: 20, weight: .bold)
        case 3: return .system(size: 17, weight: .semibold)
        case 4: return .system(size: 15, weight: .semibold)
        default: return .system(size: 14, weight: .medium)
        }
    }

    private func inlineText(_ raw: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(raw)
    }
}

private struct MarkdownTableView: View {
    let grid: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                if let headers = grid.first {
                    HStack(spacing: 0) {
                        ForEach(Array(headers.enumerated()), id: \.offset) { _, cell in
                            Text(cell)
                                .font(.system(.subheadline, design: .default).weight(.bold))
                                .frame(minWidth: 100, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                        }
                    }
                    .background(Color.secondary.opacity(0.12))
                    Divider()
                }

                ForEach(Array(grid.dropFirst().enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell)
                                .font(.system(.body, design: .default))
                                .frame(minWidth: 100, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                    }
                    .background(index.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.04))

                    if index < grid.count - 2 {
                        Divider().opacity(0.5)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1) }
        }
    }
}

@MainActor
public enum NativeFileIconProvider {
    private static var iconCache: [String: NSImage] = [:]
    private static var isPrewarmed: Bool = false

    public static let folderIcon: NSImage = {
        let icon = NSWorkspace.shared.icon(for: .folder)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }()

    public static let genericDocumentIcon: NSImage = {
        let icon = NSWorkspace.shared.icon(for: .item)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }()

    public static func prewarm() {
        guard !isPrewarmed else { return }
        isPrewarmed = true
        let commonExtensions = [
            "swift", "txt", "md", "json", "json5", "c", "h", "cpp", "py", "js", "ts",
            "html", "css", "sh", "zsh", "yml", "yaml", "toml", "xml", "csv", "tsv",
            "zip", "tar", "gz", "7z", "rar", "pdf", "png", "jpg", "jpeg", "gif",
            "sql", "db", "sqlite", "plist"
        ]
        for ext in commonExtensions {
            _ = icon(for: "file.\(ext)", isDirectory: false)
        }
    }

    public static func icon(for filename: String, isDirectory: Bool) -> NSImage {
        if isDirectory {
            return folderIcon
        }
        let ext = (filename as NSString).pathExtension.lowercased()
        let cacheKey = ext.isEmpty ? filename.lowercased() : ext
        if let cached = iconCache[cacheKey] {
            return cached
        }
        iconCache[cacheKey] = genericDocumentIcon
        Task.detached(priority: .utility) {
            let utType = ext.isEmpty ? .item : (UTType(filenameExtension: ext) ?? .item)
            let icon = NSWorkspace.shared.icon(for: utType)
            icon.size = NSSize(width: 16, height: 16)
            await MainActor.run {
                iconCache[cacheKey] = icon
            }
        }
        return genericDocumentIcon
    }
}

private func countTreeNodes(_ roots: [TreeNode]) -> (folders: Int, files: Int) {
    var folders = 0
    var files = 0
    func traverse(_ nodes: [TreeNode]) {
        for node in nodes {
            if !node.children.isEmpty {
                folders += 1
                traverse(node.children)
            } else {
                files += 1
            }
        }
    }
    traverse(roots)
    return (folders, files)
}

private struct ArchiveDetailCardView: View {
    let block: TreeBlock
    let searchText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部 Header 状态信息（与 Database 的 TableDetailCardView 风格高度一致）
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentColor)
                    Text(block.title.isEmpty ? "Archive Contents" : block.title)
                        .font(.system(size: 14, weight: .bold))
                }

                Spacer()

                HStack(spacing: 8) {
                    let counts = countTreeNodes(block.roots)
                    let itemsLabel = counts.folders > 0
                        ? "\(counts.folders + counts.files) items (\(counts.folders) folders, \(counts.files) files)"
                        : "\(counts.files) items"
                    Text(itemsLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // 滚动树主体（支持垂直平滑滚动）
            ScrollView(.vertical) {
                ArchiveTreeView(
                    roots: block.roots,
                    columns: block.columns,
                    searchText: searchText
                )
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.thinMaterial)
    }
}

private struct TreeBlockView: View {
    let block: TreeBlock
    var searchText: String = ""

    private var isOutline: Bool {
        block.title.localizedCaseInsensitiveContains("outline")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !block.title.isEmpty {
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        Image(systemName: isOutline ? "list.bullet.indent" : "archivebox.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.accentColor)
                        Text(block.title)
                            .font(.system(size: 13, weight: .bold))
                    }
                    Spacer()
                    let counts = countTreeNodes(block.roots)
                    let countText: String = {
                        if isOutline {
                            let total = counts.folders + counts.files
                            return total == 1 ? "1 section" : "\(total) sections"
                        }
                        return counts.folders > 0
                            ? "\(counts.folders + counts.files) items (\(counts.folders) folders, \(counts.files) files)"
                            : "\(counts.files) items"
                    }()
                    Text(countText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                Divider()
            }
            ArchiveTreeView(roots: block.roots, columns: block.columns, searchText: searchText)
                .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var standardTree: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(block.title)
                .font(.headline)
            OutlineGroup(block.roots, children: \.optionalChildren) { node in
                HStack(spacing: 6) {
                    Image(nsImage: NativeFileIconProvider.icon(for: node.label, isDirectory: !node.children.isEmpty))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                    Text(node.label)
                    if let value = node.value {
                        Text(value)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if node.isUnsafe {
                        Image(systemName: "exclamationmark.shield")
                            .foregroundStyle(.red)
                            .help("Unsafe archive path")
                    }
                }
            }
        }
        .padding(10)
    }
}

private struct ArchiveTreeView: View {
    let roots: [TreeNode]
    let columns: [String]?
    let searchText: String
    @State private var expandedNodeIDs: Set<UUID> = []
    @State private var visibleRows: [ArchiveTreeVisibleRow] = []

    init(roots: [TreeNode], columns: [String]? = nil, searchText: String = "") {
        self.roots = roots
        self.columns = columns
        self.searchText = searchText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let cols = columns, !cols.isEmpty {
                columnsHeader(cols)
                Divider()
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleRows.enumerated()), id: \.element.id) { index, row in
                    ArchiveTreeRow(
                        node: row.node,
                        depth: row.depth,
                        rowIndex: index,
                        searchText: searchText,
                        isExpanded: expandedNodeIDs.contains(row.node.id)
                    ) {
                        toggle(row)
                    }
                }
            }
            .padding(.top, 2)
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            NativeFileIconProvider.prewarm()
            resetVisibleRows()
        }
        .onChange(of: roots.map(\.id)) { _, _ in resetVisibleRows() }
    }

    @ViewBuilder
    private func columnsHeader(_ cols: [String]) -> some View {
        HStack(spacing: 8) {
            Text("名称")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 32)

            Spacer(minLength: 8)

            if cols.count >= 3 {
                Text(cols[0]) // 修改时间
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 125, alignment: .trailing)

                Text(cols[1]) // 压缩前
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 75, alignment: .trailing)

                Text(cols[2]) // 压缩后
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 75, alignment: .trailing)
            }

            if cols.count >= 4 {
                Text(cols[3]) // 压缩率
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 55, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04))
    }

    private func toggle(_ row: ArchiveTreeVisibleRow) {
        guard !row.node.children.isEmpty else { return }
        // Only animate the expandedNodeIDs change (drives chevron rotation).
        // Rebuild visible rows OUTSIDE the animation transaction to avoid
        // SwiftUI performing expensive insert/remove transition diff on every
        // child row, which is the root cause of UI lag on directory expand.
        withAnimation(.snappy(duration: 0.12)) {
            if expandedNodeIDs.contains(row.node.id) {
                expandedNodeIDs.remove(row.node.id)
            } else {
                expandedNodeIDs.insert(row.node.id)
            }
        }
        rebuildVisibleRows()
    }

    private func resetVisibleRows() {
        var initialExpanded = Set<UUID>()
        for root in roots where !root.children.isEmpty {
            initialExpanded.insert(root.id)
        }
        expandedNodeIDs = initialExpanded
        rebuildVisibleRows()
    }

    private func rebuildVisibleRows() {
        var result: [ArchiveTreeVisibleRow] = []
        result.reserveCapacity(roots.count * 4)
        func collect(nodes: [TreeNode], depth: Int) {
            for node in nodes {
                result.append(.init(node: node, depth: depth))
                if expandedNodeIDs.contains(node.id) && !node.children.isEmpty {
                    collect(nodes: node.children, depth: depth + 1)
                }
            }
        }
        collect(nodes: roots, depth: 0)
        visibleRows = result
    }
}

private struct ArchiveTreeVisibleRow: Identifiable {
    let node: TreeNode
    let depth: Int

    var id: UUID { node.id }
}

private struct ArchiveTreeRow: View {
    let node: TreeNode
    let depth: Int
    var rowIndex: Int = 0
    var searchText: String = ""
    let isExpanded: Bool
    let toggle: () -> Void
    @State private var isHovered: Bool = false

    private var hasChildren: Bool {
        !node.children.isEmpty
    }

    private var isMatch: Bool {
        !searchText.isEmpty && node.label.localizedCaseInsensitiveContains(searchText)
    }

    var body: some View {
        Group {
            if hasChildren {
                Button(action: toggle) {
                    rowContent
                }
                .buttonStyle(InstantRowButtonStyle())
            } else {
                rowContent
            }
        }
        .onHover { isHovered = $0 }
    }

    private var rowContent: some View {
        HStack(spacing: 6) {
            if hasChildren {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 14, height: 18)
            } else {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 14, height: 18)
            }

            Image(nsImage: NativeFileIconProvider.icon(for: node.label, isDirectory: hasChildren))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)

            Text(node.label)
                .font(.system(size: 13, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(isMatch ? Color.accentColor : Color.primary)
                .fontWeight(isMatch ? .semibold : .regular)

            if node.isUnsafe {
                Image(systemName: "exclamationmark.shield")
                    .foregroundStyle(.red)
                    .help("Unsafe archive path")
            }

            Spacer(minLength: 8)

            if let cols = node.detailColumns, cols.count >= 3 {
                HStack(spacing: 8) {
                    Text(cols[0])
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 125, alignment: .trailing)

                    Text(cols[1])
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 75, alignment: .trailing)

                    Text(cols[2])
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(cols[1] != cols[2] && cols[2] != "-" ? Color.accentColor : Color.secondary)
                        .frame(width: 75, alignment: .trailing)

                    if cols.count >= 4 {
                        Text(cols[3])
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(cols[3] != "-" && cols[3] != "100%" ? Color.accentColor : Color.secondary)
                            .frame(width: 55, alignment: .trailing)
                    }
                }
            } else if let value = node.value, !value.isEmpty {
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.leading, CGFloat(depth) * 18)
        .padding(.vertical, 3)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.secondary.opacity(0.08) : (rowIndex % 2 == 1 ? Color.primary.opacity(0.02) : Color.clear))
        )
    }
}

private struct TableBlockView: View {
    let block: TableBlock
    let searchText: String

    private var rows: [[String]] {
        guard !searchText.isEmpty else { return block.rows }
        return block.rows.filter { $0.joined(separator: " ").localizedCaseInsensitiveContains(searchText) }
    }

    private func columnWidth(at index: Int) -> CGFloat {
        var maxChars = index < block.columns.count ? block.columns[index].count : 4
        for row in rows.prefix(30) {
            if index < row.count {
                maxChars = max(maxChars, row[index].count)
            }
        }
        let calculated = CGFloat(maxChars) * 8.5 + 24
        return max(70, min(320, calculated))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部标题状态栏（若 title 非空）
            if !block.title.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text(block.title)
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Text("\(rows.count) rows · \(block.columns.count) columns")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                Divider()
            }

            // 表格数据主体
            ScrollView(.horizontal, showsIndicators: rows.count > 10) {
                VStack(alignment: .leading, spacing: 0) {
                    // 表头行
                    HStack(spacing: 0) {
                        ForEach(Array(block.columns.enumerated()), id: \.offset) { offset, column in
                            Text(column)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: columnWidth(at: offset), alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                            if offset < block.columns.count - 1 {
                                Divider().frame(height: 16)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .background(Color.primary.opacity(0.04))

                    Divider()

                    // 数据行
                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cellValue in
                                Text(cellValue)
                                    .font(.system(size: 12, design: .monospaced))
                                    .textSelection(.enabled)
                                    .lineLimit(2)
                                    .frame(minWidth: columnWidth(at: colIndex), alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                if colIndex < row.count - 1 {
                                    Divider().frame(height: 14).opacity(0.3)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .background(rowIndex % 2 == 1 ? Color.primary.opacity(0.02) : Color.clear)
                        Divider().opacity(0.4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct ErrorBlockView: View {
    let block: ErrorBlock

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(block.title).font(.headline)
                Text(block.message)
                if let recoverySuggestion = block.recoverySuggestion {
                    Text(recoverySuggestion).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
    }
}

private struct MetadataFooter: View {
    let items: [MetadataItem]
    let warnings: [PreviewWarning]

    var body: some View {
        HStack(spacing: 8) {
            if let warning = warnings.first {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(warning.message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            } else if !items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(items) { item in
                            Text("\(item.key): \(item.value)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.9))
                Text("PreviewX")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.85))
                Text("·")
                    .font(.system(size: 9, weight: .light))
                    .foregroundStyle(.secondary.opacity(0.45))
                Text("by idcpj")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
    }
}
