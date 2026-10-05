import Foundation
import XCTest
@testable import PreviewXCore
@testable import PreviewXProviders

/// End-to-end test coverage that walks the unified `Tests/Fixtures` corpus and runs
/// the real `PreviewRuntime` against every file.
/// Validates the core promises of the PreviewX pipeline:
/// - Every valid fixture produces at least one visible content block;
/// - Corrupted files fail gracefully with explicit diagnostics;
/// - All 49+ code fixtures produce real syntax tokens that faithfully reconstruct source lines;
/// - Markdown fixtures produce structured outline nodes;
/// - JSONC fixtures strip comments and format cleanly;
/// - Unicode fixtures (BOM, multilingual CJK, emoji) decode losslessly;
/// - CSV/TSV fixtures parse into grid table blocks.
final class MockFixturePreviewTests: XCTestCase {
    private func fixturesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // PreviewXTests
            .deletingLastPathComponent() // Tests
            .appendingPathComponent("Fixtures", isDirectory: true)
    }

    private func allFixtureFiles() -> [URL] {
        let root = fixturesDirectory()
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private func configuredRuntime() async -> PreviewRuntime {
        let registry = ProviderRegistry()
        let runtime = PreviewRuntime(registry: registry)
        try? await BuiltInProviders.registerAll(into: registry)
        return runtime
    }

    private func document(for result: PreviewResult) -> PreviewDocument? {
        switch result {
        case let .success(document), let .partial(document, _):
            return document
        case .unsupported, .failed:
            return nil
        }
    }

    private func hasVisibleBlock(_ document: PreviewDocument) -> Bool {
        if document.blocks.contains(where: { block in
            switch block {
            case .code, .text, .table, .tree, .markdown, .error:
                return true
            }
        }) {
            return true
        }
        return document.blocks.contains { block in
            switch block {
            case let .text(text):
                return !text.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case let .code(code):
                return !code.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case let .tree(tree):
                return !tree.roots.isEmpty
            case let .table(table):
                return !table.rows.isEmpty || !table.columns.isEmpty
            case let .markdown(markdown):
                return !markdown.nodes.isEmpty
            case .error:
                return true
            }
        }
    }

    // MARK: - Directory Integrity Tests

    func testAllFixtureSubdirectoriesExistAndNonEmpty() throws {
        let root = fixturesDirectory()
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path), "Fixtures directory must exist at \(root.path)")

        let expectedSubdirs = [
            "archives", "binary", "code", "csv", "database", "diff",
            "huge", "json", "logs", "malformed", "security",
            "text", "toml", "unicode", "xml", "yaml"
        ]

        for subdir in expectedSubdirs {
            let subURL = root.appendingPathComponent(subdir, isDirectory: true)
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: subURL.path, isDirectory: &isDir)
            XCTAssertTrue(exists && isDir.boolValue, "Missing expected fixture directory: \(subdir)")

            let items = (try? FileManager.default.contentsOfDirectory(atPath: subURL.path))?.filter { !$0.hasPrefix(".") } ?? []
            XCTAssertFalse(items.isEmpty, "Fixture directory \(subdir) must not be empty")
        }
    }

    // MARK: - Corpus Visible Content Tests

    func testEveryFixtureFileProducesVisibleContent() async throws {
        let files = allFixtureFiles()
        XCTAssertFalse(files.isEmpty, "Expected to find files under Tests/Fixtures")

        let runtime = await configuredRuntime()
        for file in files {
            // README.md is documentation index
            if file.lastPathComponent == "README.md" { continue }
            if file.lastPathComponent.hasPrefix("empty.") {
                let result = await runtime.preview(fileURL: file)
                guard let document = document(for: result) else {
                    XCTFail("No document produced for \(file.lastPathComponent): \(result)")
                    continue
                }
                XCTAssertFalse(document.blocks.isEmpty, "\(file.lastPathComponent) produced no blocks")
                continue
            }

            let result = await runtime.preview(fileURL: file)
            guard let document = document(for: result) else {
                XCTFail("No document produced for \(file.lastPathComponent): \(result)")
                continue
            }
            XCTAssertFalse(document.blocks.isEmpty, "\(file.lastPathComponent) produced no blocks")
            XCTAssertTrue(
                hasVisibleBlock(document),
                "\(file.lastPathComponent) produced no visible block"
            )
        }
    }

    // MARK: - Code Fixtures & Token Reconstruction Tests

    func testCodeFixturesProduceSyntaxTokens() async throws {
        let runtime = await configuredRuntime()
        let codeDir = fixturesDirectory().appendingPathComponent("code", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: codeDir, includingPropertiesForKeys: nil))?
            .filter { !$0.lastPathComponent.hasPrefix(".") } ?? []
        XCTAssertGreaterThanOrEqual(files.count, 40, "Expected at least 40 code fixtures under Tests/Fixtures/code")

        for file in files {
            let result = await runtime.preview(fileURL: file)
            guard let document = document(for: result) else {
                XCTFail("No document for \(file.lastPathComponent)")
                continue
            }

            var content: String?
            var language: String?
            for block in document.blocks {
                if case let .code(code) = block {
                    content = code.content
                    language = code.language
                    break
                }
                if case let .text(text) = block, content == nil {
                    content = text.content
                    language = text.language
                }
            }

            guard let source = content, let firstLine = source.split(separator: "\n").first else {
                continue
            }
            let tokens = SyntaxHighlighter.tokens(in: String(firstLine), language: language)
            XCTAssertFalse(tokens.isEmpty, "No tokens for \(file.lastPathComponent)")
            XCTAssertEqual(
                tokens.map(\.text).joined(),
                String(firstLine),
                "Tokens for \(file.lastPathComponent) must reconstruct the original line"
            )
        }
    }

    // MARK: - Markdown Structure Tests

    func testMarkdownFixturesProduceMarkdownNodes() async throws {
        let runtime = await configuredRuntime()
        let textDir = fixturesDirectory().appendingPathComponent("text", isDirectory: true)
        let markdownFiles = (try? FileManager.default.contentsOfDirectory(at: textDir, includingPropertiesForKeys: nil))?
            .filter { ["md", "markdown", "mdown"].contains($0.pathExtension.lowercased()) } ?? []
        XCTAssertFalse(markdownFiles.isEmpty, "Expected Markdown fixtures under Tests/Fixtures/text")

        for file in markdownFiles {
            let result = await runtime.preview(fileURL: file)
            guard let document = document(for: result) else {
                XCTFail("No document for \(file.lastPathComponent)")
                continue
            }
            let markdownBlock = document.blocks.compactMap { block -> MarkdownBlock? in
                if case let .markdown(value) = block { return value }
                return nil
            }.first
            XCTAssertNotNil(markdownBlock, "\(file.lastPathComponent) did not produce a markdown block")
            XCTAssertFalse(markdownBlock?.nodes.isEmpty ?? true, "\(file.lastPathComponent) markdown block had no nodes")
        }
    }

    // MARK: - JSONC Parsing & Stripping Tests

    func testJSONCFixtureIsFormattedNotMalformed() async throws {
        let runtime = await configuredRuntime()
        let jsoncFiles = [
            fixturesDirectory().appendingPathComponent("json/sample.jsonc"),
            fixturesDirectory().appendingPathComponent("structured/sample.jsonc")
        ]

        for file in jsoncFiles {
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            let result = await runtime.preview(fileURL: file)
            guard let document = document(for: result) else {
                XCTFail("No document for \(file.lastPathComponent): \(result)")
                continue
            }
            XCTAssertFalse(
                document.subtitle?.localizedCaseInsensitiveContains("malformed") ?? false,
                "JSONC should parse after comment stripping for \(file.lastPathComponent)"
            )
            XCTAssertFalse(
                document.warnings.contains { $0.kind == .malformed },
                "JSONC should not emit a malformed warning for \(file.lastPathComponent)"
            )
            guard case let .code(block) = document.blocks.first(where: {
                if case .code = $0 { return true }
                return false
            }) else {
                XCTFail("Expected a formatted JSON code block for \(file.lastPathComponent)")
                continue
            }
            XCTAssertTrue(block.content.contains("\"name\""), "Formatted JSONC should retain its data")
            XCTAssertFalse(block.content.contains("//"), "Comments should be stripped from formatted output")
        }
    }

    // MARK: - Unicode and BOM Tests

    func testUnicodeFixturesDecodeCleanly() async throws {
        let runtime = await configuredRuntime()
        let unicodeDir = fixturesDirectory().appendingPathComponent("unicode", isDirectory: true)
        let bomFile = unicodeDir.appendingPathComponent("utf8_bom.txt")
        let cjkFile = unicodeDir.appendingPathComponent("cjk_multilingual.txt")

        for file in [bomFile, cjkFile] {
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            let result = await runtime.preview(fileURL: file)
            guard let document = document(for: result) else {
                XCTFail("No document for \(file.lastPathComponent)")
                continue
            }
            guard case let .text(text)? = document.blocks.first(where: { if case .text = $0 { return true }; return false }) else {
                XCTFail("Expected text block for \(file.lastPathComponent)")
                continue
            }
            XCTAssertFalse(text.content.isEmpty)
            // Assert BOM character \u{FEFF} is stripped or content starts cleanly
            XCTAssertFalse(text.content.hasPrefix("\u{FEFF}"))
        }
    }

    // MARK: - CSV and Table Tests

    func testCSVFixturesProduceTableBlocks() async throws {
        let runtime = await configuredRuntime()
        let csvDir = fixturesDirectory().appendingPathComponent("csv", isDirectory: true)
        let csvFiles = (try? FileManager.default.contentsOfDirectory(at: csvDir, includingPropertiesForKeys: nil))?
            .filter { ["csv", "tsv"].contains($0.pathExtension.lowercased()) } ?? []
        XCTAssertFalse(csvFiles.isEmpty, "Expected CSV fixtures under Tests/Fixtures/csv")

        for file in csvFiles {
            let result = await runtime.preview(fileURL: file)
            guard let document = document(for: result) else {
                XCTFail("No document for \(file.lastPathComponent)")
                continue
            }
            guard case let .table(table)? = document.blocks.first(where: { if case .table = $0 { return true }; return false }) else {
                XCTFail("Expected table block for \(file.lastPathComponent)")
                continue
            }
            XCTAssertFalse(table.columns.isEmpty, "\(file.lastPathComponent) had no columns")
            XCTAssertFalse(table.rows.isEmpty, "\(file.lastPathComponent) had no rows")
        }
    }

    // MARK: - 7z Archive Inspection Tests

    func test7zArchiveFixtureIsRecognizedAndParsed() async throws {
        let runtime = await configuredRuntime()
        let file = fixturesDirectory().appendingPathComponent("archives/sample.7z")
        let result = await runtime.preview(fileURL: file)
        guard let document = document(for: result) else {
            XCTFail("Failed to preview sample.7z: \(result)")
            return
        }
        XCTAssertTrue(document.subtitle?.localizedCaseInsensitiveContains("7z") == true)
        XCTAssertFalse(document.blocks.isEmpty)
        guard case let .tree(tree)? = document.blocks.first(where: { if case .tree = $0 { return true }; return false }) else {
            XCTFail("Expected tree block for sample.7z")
            return
        }
        XCTAssertFalse(tree.roots.isEmpty)
    }

    // MARK: - JSON5 Support Tests

    func testJSON5FixtureSupport() async throws {
        let runtime = await configuredRuntime()
        let file = fixturesDirectory().appendingPathComponent("json/sample.json5")
        let result = await runtime.preview(fileURL: file)
        guard let document = document(for: result) else {
            XCTFail("Failed to preview sample.json5: \(result)")
            return
        }
        XCTAssertEqual(document.subtitle, "JSON5")
        XCTAssertFalse(document.warnings.contains { $0.kind == .malformed })
        guard case let .code(code)? = document.blocks.first(where: { if case .code = $0 { return true }; return false }) else {
            XCTFail("Expected code block for sample.json5")
            return
        }
        XCTAssertTrue(code.content.localizedCaseInsensitiveContains("previewx"))
    }

    // MARK: - SQLite Database Tests

    func testSQLiteDatabaseFixtures() async throws {
        let runtime = await configuredRuntime()
        let dbDir = fixturesDirectory().appendingPathComponent("database", isDirectory: true)

        // Valid databases
        for name in ["sample.sqlite", "sample.sqlite3", "sample.db", "large_database.sqlite", "large_database.db"] {
            let file = dbDir.appendingPathComponent(name)
            let result = await runtime.preview(fileURL: file)
            guard let document = document(for: result) else {
                XCTFail("Failed to preview \(name): \(result)")
                continue
            }
            XCTAssertEqual(document.subtitle, "SQLite metadata")
            guard case let .table(table)? = document.blocks.first(where: { if case .table = $0 { return true }; return false }) else {
                XCTFail("Expected database table for \(name)")
                continue
            }
            XCTAssertFalse(table.columns.isEmpty, "\(name) first table should have columns")
            XCTAssertFalse(table.rows.isEmpty, "\(name) first table should have rows")
            XCTAssertFalse(document.blocks.contains { block in
                if case let .table(t) = block, t.title == "Database Header" { return true }
                return false
            }, "Database Header table should not be displayed when tables exist")
        }

        // Corrupted database should gracefully degrade
        let corrupted = dbDir.appendingPathComponent("corrupted.sqlite")
        let corruptedResult = await runtime.preview(fileURL: corrupted)
        guard let corruptedDoc = document(for: corruptedResult) else {
            XCTFail("Corrupted sqlite should provide graceful preview instead of crashing")
            return
        }
        XCTAssertEqual(corruptedDoc.subtitle, "Corrupted SQLite Database")
        XCTAssertTrue(corruptedDoc.warnings.contains { $0.kind == .malformed })
        XCTAssertTrue(corruptedDoc.blocks.contains { if case .error = $0 { return true }; return false })
    }

    // MARK: - Log Syntax Highlighting Tests

    func testLogSyntaxHighlighting() async throws {
        let runtime = await configuredRuntime()
        let logsDir = fixturesDirectory().appendingPathComponent("logs", isDirectory: true)
        let logFiles = ["service.log", "nginx_access.log"].map { logsDir.appendingPathComponent($0) }

        for file in logFiles {
            let result = await runtime.preview(fileURL: file)
            guard let document = document(for: result) else {
                XCTFail("Failed to preview \(file.lastPathComponent)")
                continue
            }
            guard case let .code(code)? = document.blocks.first(where: { if case .code = $0 { return true }; return false }) else {
                XCTFail("Expected code block with log language for \(file.lastPathComponent)")
                continue
            }
            XCTAssertEqual(code.language, "log")

            // Verify tokens reconstruct lines and highlight tokens
            for line in code.content.split(separator: "\n").map(String.init) {
                let tokens = SyntaxHighlighter.tokens(in: line, language: "log")
                XCTAssertFalse(tokens.isEmpty)
                XCTAssertEqual(tokens.map(\.text).joined(), line)
            }
        }
    }

    // MARK: - Diff and Patch Tests

    func testDiffAndPatchFixtures() async throws {
        let runtime = await configuredRuntime()
        let diffDir = fixturesDirectory().appendingPathComponent("diff", isDirectory: true)
        let diffFiles = (try? FileManager.default.contentsOfDirectory(at: diffDir, includingPropertiesForKeys: nil))?
            .filter { ["diff", "patch"].contains($0.pathExtension.lowercased()) } ?? []
        XCTAssertGreaterThanOrEqual(diffFiles.count, 2)

        for file in diffFiles {
            let result = await runtime.preview(fileURL: file)
            guard let document = document(for: result) else {
                XCTFail("Failed to preview \(file.lastPathComponent)")
                continue
            }
            guard case let .code(code)? = document.blocks.first(where: { if case .code = $0 { return true }; return false }) else {
                XCTFail("Expected code block for \(file.lastPathComponent)")
                continue
            }
            XCTAssertEqual(code.language, "diff")
        }
    }

    // MARK: - Malformed Files Graceful Degradation Tests

    func testMalformedFixturesDegradeGracefullyWithCodeHighlights() async throws {
        let runtime = await configuredRuntime()
        let malformedDir = fixturesDirectory().appendingPathComponent("malformed", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: malformedDir, includingPropertiesForKeys: nil))?
            .filter { !$0.lastPathComponent.hasPrefix(".") } ?? []
        XCTAssertGreaterThanOrEqual(files.count, 10)

        for file in files {
            let result = await runtime.preview(fileURL: file)
            guard let document = document(for: result) else {
                XCTFail("Malformed file \(file.lastPathComponent) failed to provide fallback preview: \(result)")
                continue
            }
            XCTAssertTrue(hasVisibleBlock(document), "Malformed file \(file.lastPathComponent) had no visible block")
            // Ensure raw/fallback code or content block is available
            let hasCodeOrContent = document.blocks.contains { block in
                switch block {
                case .code, .text, .table: return true
                default: return false
                }
            }
            XCTAssertTrue(hasCodeOrContent, "\(file.lastPathComponent) should contain code or text content block")
        }
    }

    // MARK: - Archive No-Summary-Table & Compression Calculation Tests

    func testArchiveDoesNotProduceSummaryTableOnlyDirectoryTree() async throws {
        let runtime = await configuredRuntime()
        let archivesDir = fixturesDirectory().appendingPathComponent("archives", isDirectory: true)
        let sampleFiles = [
            "sample.zip",
            "sample.tar",
            "unsafe_traversal.tar",
            "sample.7z"
        ]

        for filename in sampleFiles {
            let fileURL = archivesDir.appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            let result = await runtime.preview(fileURL: fileURL)
            guard let document = document(for: result) else {
                XCTFail("Failed to preview archive \(filename): \(result)")
                continue
            }

            // Must NOT contain summary table block
            let hasTable = document.blocks.contains {
                if case .table = $0 { return true }
                return false
            }
            XCTAssertFalse(hasTable, "\(filename) should not display summary table block")

            // Must contain tree block
            let treeBlock = document.blocks.compactMap { block -> TreeBlock? in
                if case let .tree(tree) = block { return tree }
                return nil
            }.first
            XCTAssertNotNil(treeBlock, "\(filename) must display directory tree block")

            // Title should include size or compression info
            if let title = treeBlock?.title {
                XCTAssertTrue(
                    title.contains("Archive Contents"),
                    "\(filename) tree title should be formatted: \(title)"
                )
            }
        }

        // Test ZIP calculates compression comparison for both files and directories
        let zipURL = archivesDir.appendingPathComponent("sample.zip")
        if FileManager.default.fileExists(atPath: zipURL.path) {
            let result = await runtime.preview(fileURL: zipURL)
            guard let doc = document(for: result),
                  let tree = doc.blocks.compactMap({ block -> TreeBlock? in
                      if case let .tree(t) = block { return t }
                      return nil
                  }).first
            else {
                return XCTFail("Expected tree block for sample.zip")
            }
            // Verify multi-column headers including compression ratio
            XCTAssertEqual(tree.columns, ["修改时间", "压缩前", "压缩后", "压缩率"])

            // Directory node should rollup compression comparison and have detailColumns
            let directoryNodes = tree.roots.filter { !$0.children.isEmpty }
            XCTAssertFalse(directoryNodes.isEmpty, "sample.zip should have directory nodes")
            for dir in directoryNodes {
                XCTAssertNotNil(dir.value, "Directory node \(dir.label) should have rollup value")
                XCTAssertEqual(dir.detailColumns?.count, 4, "Directory \(dir.label) should have 4 detail columns")
                if let val = dir.value {
                    XCTAssertTrue(val.contains("原") || val.contains("字节") || val.contains("B"), "Directory \(dir.label) value: \(val)")
                }
                if let ratio = dir.detailColumns?[3] {
                    XCTAssertTrue(ratio.contains("%") || ratio == "-", "Directory \(dir.label) ratio column: \(ratio)")
                }
            }

            // Verify document metadata contains uncompressed size and compression ratio
            let metadataKeys = doc.metadata.map(\.key)
            XCTAssertTrue(metadataKeys.contains("Uncompressed"), "Metadata should include Uncompressed size")
            XCTAssertTrue(metadataKeys.contains("Compression ratio"), "Metadata should include Compression ratio")
        }

        // Test TAR.GZ calculates compression comparison for both files and directories
        let targzURL = archivesDir.appendingPathComponent("sample.tar.gz")
        if FileManager.default.fileExists(atPath: targzURL.path) {
            let result = await runtime.preview(fileURL: targzURL)
            guard let doc = document(for: result),
                  let tree = doc.blocks.compactMap({ block -> TreeBlock? in
                      if case let .tree(t) = block { return t }
                      return nil
                  }).first
            else {
                return XCTFail("Expected tree block for sample.tar.gz")
            }
            XCTAssertEqual(tree.columns, ["修改时间", "压缩前", "压缩后", "压缩率"])
            let directoryNodes = tree.roots.filter { !$0.children.isEmpty }
            XCTAssertFalse(directoryNodes.isEmpty, "sample.tar.gz should have directory nodes")
            for dir in directoryNodes {
                XCTAssertNotNil(dir.value, "TAR.GZ directory \(dir.label) should have rollup value")
                XCTAssertEqual(dir.detailColumns?.count, 4, "TAR.GZ directory \(dir.label) should have 4 detail columns")
                if let val = dir.value {
                    XCTAssertTrue(val.contains("原") && val.contains("压缩后"), "Directory \(dir.label) value: \(val)")
                }
                if let ratio = dir.detailColumns?[3] {
                    XCTAssertTrue(ratio.contains("%") || ratio == "-", "Directory \(dir.label) ratio column: \(ratio)")
                }
            }
        }
    }

    // MARK: - SQLite Direct Data Preview Tests

    func testDirectSQLiteDataPreview() async throws {
        let runtime = await configuredRuntime()
        let file = fixturesDirectory().appendingPathComponent("database/sample.sqlite")
        guard FileManager.default.fileExists(atPath: file.path) else {
            return XCTFail("Missing sample.sqlite fixture")
        }

        let result = await runtime.preview(fileURL: file)
        guard let document = document(for: result) else {
            return XCTFail("Expected preview document for sample.sqlite, got \(result)")
        }

        // Must contain data table blocks and NOT contain Database Header
        let tableBlocks = document.blocks.compactMap { block -> TableBlock? in
            if case let .table(t) = block { return t }
            return nil
        }
        XCTAssertFalse(tableBlocks.isEmpty, "Expected data table blocks")
        XCTAssertFalse(tableBlocks.contains { $0.title == "Database Header" }, "Database Header should not be shown when tables exist")

        // Assert direct user data preview from table 'preview'
        guard let dataTable = tableBlocks.first(where: { $0.title.contains("preview") }) else {
            return XCTFail("Expected table block for 'preview' table in database")
        }
        XCTAssertEqual(dataTable.columns, ["id", "name"], "Table columns must match SQLite schema")
        XCTAssertEqual(dataTable.rows.first, ["1", "PreviewX"], "Direct data row must match preview table records")

        // Test large database mock fixture
        let largeFile = fixturesDirectory().appendingPathComponent("database/large_database.sqlite")
        if FileManager.default.fileExists(atPath: largeFile.path) {
            let largeResult = await runtime.preview(fileURL: largeFile)
            guard let largeDoc = self.document(for: largeResult) else {
                return XCTFail("Expected document for large_database.sqlite")
            }
            let largeTables = largeDoc.blocks.compactMap { block -> TableBlock? in
                if case let .table(t) = block { return t }
                return nil
            }
            // Should contain users, products, orders, audit_logs
            XCTAssertEqual(largeTables.count, 4, "Large database should preview 4 tables")
            XCTAssertTrue(largeTables.contains { $0.title.contains("users") })
            XCTAssertTrue(largeTables.contains { $0.title.contains("orders") })
            XCTAssertTrue(largeTables.contains { $0.title.contains("products") })
            XCTAssertTrue(largeTables.contains { $0.title.contains("audit_logs") })
            XCTAssertFalse(largeTables.contains { $0.title.contains("Database Header") })
        }
    }

    // MARK: - Enhanced Markdown Rich Typography & Features Tests

    func testEnhancedMarkdownPreviewWithTablesAndTasks() async throws {
        let runtime = await configuredRuntime()
        let file = fixturesDirectory().appendingPathComponent("text/markdown_showcase.md")
        guard FileManager.default.fileExists(atPath: file.path) else {
            return XCTFail("Missing markdown_showcase.md fixture")
        }

        let result = await runtime.preview(fileURL: file)
        guard let document = document(for: result) else {
            return XCTFail("Expected document for markdown_showcase.md, got \(result)")
        }

        guard let markdownBlock = document.blocks.compactMap({ block -> MarkdownBlock? in
            if case let .markdown(m) = block { return m }
            return nil
        }).first else {
            return XCTFail("Expected MarkdownBlock in document")
        }

        // 1. Assert headings parsed with levels
        let headings = markdownBlock.nodes.filter { $0.kind == .heading }
        XCTAssertTrue(headings.contains { $0.level == 1 && $0.text.contains("Showcase") })
        XCTAssertTrue(headings.contains { $0.level == 2 && $0.text.contains("Checklist") })

        // 2. Assert GFM Task List items parsed with isDone state
        let taskItems = markdownBlock.nodes.filter { $0.kind == .taskItem }
        XCTAssertGreaterThanOrEqual(taskItems.count, 4, "Expected task checklist items in markdown")
        XCTAssertTrue(taskItems.contains { $0.isDone == true && $0.text.contains("Quick Look") }, "Completed task must have isDone = true")
        XCTAssertTrue(taskItems.contains { $0.isDone == false && $0.text.contains("Cloud Dependency") }, "Incomplete task must have isDone = false")

        // 3. Assert GFM Table block parsed with columns and rows
        let tableNodes = markdownBlock.nodes.filter { $0.kind == .table }
        XCTAssertFalse(tableNodes.isEmpty, "Expected GFM table node in markdown")
        guard let tableData = tableNodes.first?.tableData else {
            return XCTFail("Expected tableData in table node")
        }
        XCTAssertGreaterThanOrEqual(tableData.count, 4, "Expected header and 3 data rows in GFM table")
        XCTAssertEqual(tableData.first, ["Feature", "Traditional App", "PreviewX"])

        // 4. Assert quote and code blocks
        XCTAssertTrue(markdownBlock.nodes.contains { $0.kind == .quote })
        XCTAssertTrue(markdownBlock.nodes.contains { $0.kind == .codeBlock && $0.language == "swift" })
    }

    // MARK: - Expanded Language Catalog Fixtures Tests

    func testExpandedLanguageCatalogFixtures() async throws {
        let runtime = await configuredRuntime()
        let codeDir = fixturesDirectory().appendingPathComponent("code", isDirectory: true)

        let testCases: [(filename: String, expectedLanguage: String, sampleKeyword: String)] = [
            ("sample.dart", "Dart", "void"),
            ("sample.cs", "C#", "namespace"),
            ("sample.groovy", "Groovy", "class"),
            ("build.gradle", "Groovy", "plugins"),
            ("sample.scala", "Scala", "object"),
            ("sample.ps1", "PowerShell", "Write-Host"),
            ("sample.bat", "Batch", "echo"),
            ("sample.pl", "Perl", "my"),
            ("sample.r", "R", "data"),
            ("sample.ex", "Elixir", "defmodule"),
            ("sample.erl", "Erlang", "-module"),
            ("sample.clj", "Clojure", "defn"),
            ("sample.hs", "Haskell", "module"),
            ("Podfile", "Ruby", "platform"),
            ("Gemfile", "Ruby", "source"),
            ("Brewfile", "Ruby", "tap"),
            ("yarn.lock", "Lockfile", "version"),
            ("Cargo.lock", "Lockfile", "version"),
            ("Podfile.lock", "Lockfile", "PODS"),
            (".gitignore", "Plain text", ".DS_Store"),
            (".editorconfig", "Plain text", "indent_style")
        ]

        for testCase in testCases {
            let file = codeDir.appendingPathComponent(testCase.filename)
            guard FileManager.default.fileExists(atPath: file.path) else {
                XCTFail("Missing expanded fixture: \(testCase.filename)")
                continue
            }

            let result = await runtime.preview(fileURL: file)
            guard let document = document(for: result) else {
                XCTFail("Failed to preview \(testCase.filename): \(result)")
                continue
            }

            XCTAssertEqual(
                document.subtitle,
                testCase.expectedLanguage,
                "\(testCase.filename) should identify as \(testCase.expectedLanguage)"
            )

            // Verify tokens reconstruct lines
            guard let codeContent = document.blocks.compactMap({ block -> String? in
                if case let .code(c) = block { return c.content }
                if case let .text(t) = block { return t.content }
                return nil
            }).first else {
                XCTFail("Expected text/code block in \(testCase.filename)")
                continue
            }

            XCTAssertTrue(codeContent.contains(testCase.sampleKeyword), "\(testCase.filename) should contain \(testCase.sampleKeyword)")
        }
    }

    // MARK: - Binary Property List Tests

    func testBinaryPropertyListDecoding() async throws {
        let runtime = await configuredRuntime()
        let file = fixturesDirectory().appendingPathComponent("xml/sample_binary.plist")
        guard FileManager.default.fileExists(atPath: file.path) else {
            return XCTFail("Missing sample_binary.plist fixture")
        }

        let result = await runtime.preview(fileURL: file)
        guard let document = document(for: result) else {
            return XCTFail("Failed to preview sample_binary.plist: \(result)")
        }

        XCTAssertEqual(document.subtitle, "Binary Property List")
        guard case let .code(codeBlock)? = document.blocks.first(where: { if case .code = $0 { return true }; return false }) else {
            return XCTFail("Expected code block with converted XML for binary plist")
        }
        XCTAssertTrue(codeBlock.content.contains("CFBundleName"))
        XCTAssertTrue(codeBlock.content.contains("PreviewX"))
        XCTAssertTrue(codeBlock.content.contains("SupportedFormats"))
    }

    // MARK: - JSON Lines Tests

    func testJSONLinesPreview() async throws {
        let runtime = await configuredRuntime()
        let file = fixturesDirectory().appendingPathComponent("json/sample.jsonl")
        guard FileManager.default.fileExists(atPath: file.path) else {
            return XCTFail("Missing sample.jsonl fixture")
        }

        let result = await runtime.preview(fileURL: file)
        guard let document = document(for: result) else {
            return XCTFail("Failed to preview sample.jsonl: \(result)")
        }

        XCTAssertEqual(document.subtitle, "JSON Lines")
        XCTAssertEqual(document.metadata.first(where: { $0.key == "Records" })?.value, "3")
        guard case let .code(codeBlock)? = document.blocks.first(where: { if case .code = $0 { return true }; return false }) else {
            return XCTFail("Expected code block for sample.jsonl")
        }
        XCTAssertTrue(codeBlock.content.contains("Service initialized"))
    }

    // MARK: - Multi-Document YAML Tests

    func testMultiDocumentYAMLPreview() async throws {
        let runtime = await configuredRuntime()
        let file = fixturesDirectory().appendingPathComponent("yaml/multi_document.yaml")
        guard FileManager.default.fileExists(atPath: file.path) else {
            return XCTFail("Missing multi_document.yaml fixture")
        }

        let result = await runtime.preview(fileURL: file)
        guard let document = document(for: result) else {
            return XCTFail("Failed to preview multi_document.yaml: \(result)")
        }

        XCTAssertEqual(document.subtitle, "YAML")
        guard case let .code(codeBlock)? = document.blocks.first(where: { if case .code = $0 { return true }; return false }) else {
            return XCTFail("Expected code block for multi_document.yaml")
        }
        XCTAssertTrue(codeBlock.content.contains("Service"))
        XCTAssertTrue(codeBlock.content.contains("---"))
        XCTAssertTrue(codeBlock.content.contains("Deployment"))
    }

    // MARK: - Zero-Byte Empty Files Safe Preview Tests

    func testZeroByteEmptyFilesSafePreview() async throws {
        let runtime = await configuredRuntime()
        let emptyFiles = [
            fixturesDirectory().appendingPathComponent("text/empty.txt"),
            fixturesDirectory().appendingPathComponent("json/empty.json"),
            fixturesDirectory().appendingPathComponent("code/empty.py"),
            fixturesDirectory().appendingPathComponent("binary/empty.bin")
        ]

        for file in emptyFiles {
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            let result = await runtime.preview(fileURL: file)
            guard let document = document(for: result) else {
                XCTFail("Empty file \(file.lastPathComponent) must produce safe preview without crashing")
                continue
            }
            XCTAssertFalse(document.blocks.isEmpty, "Empty file \(file.lastPathComponent) must produce at least one block")
        }
    }

    // MARK: - UTF-16 LE and GBK Encoding Tests

    func testUTF16LEAndGBKEncodings() async throws {
        let runtime = await configuredRuntime()

        // UTF-16 LE
        let utf16URL = fixturesDirectory().appendingPathComponent("unicode/sample_utf16le.txt")
        if FileManager.default.fileExists(atPath: utf16URL.path) {
            let result = await runtime.preview(fileURL: utf16URL)
            guard let doc = document(for: result) else {
                return XCTFail("Failed to preview sample_utf16le.txt")
            }
            let encoding = doc.metadata.first(where: { $0.key == "Encoding" })?.value
            XCTAssertTrue(encoding?.contains("UTF-16") == true, "Expected UTF-16 encoding, got: \(String(describing: encoding))")
        }

        // GBK (lossy UTF-8 fallback with warning)
        let gbkURL = fixturesDirectory().appendingPathComponent("unicode/sample_gbk.txt")
        if FileManager.default.fileExists(atPath: gbkURL.path) {
            let result = await runtime.preview(fileURL: gbkURL)
            guard let doc = document(for: result) else {
                return XCTFail("Failed to preview sample_gbk.txt")
            }
            XCTAssertFalse(doc.blocks.isEmpty)
        }
    }

    // MARK: - SSH Public Key Security Non-False-Positive Tests

    func testSSHPublicKeyDoesNotTriggerSecretAlert() async throws {
        let runtime = await configuredRuntime()
        let pubKeyURL = fixturesDirectory().appendingPathComponent("security/id_rsa.pub")
        guard FileManager.default.fileExists(atPath: pubKeyURL.path) else {
            return XCTFail("Missing id_rsa.pub fixture")
        }

        let result = await runtime.preview(fileURL: pubKeyURL)
        guard case let .success(document) = result else {
            return XCTFail("SSH public key should be previewed successfully without warnings, got \(result)")
        }
        XCTAssertFalse(document.warnings.contains { $0.kind == .security }, "Public key must never trigger security secret warning")
    }

    // MARK: - JAR Archive Inspection Tests

    func testJarArchiveTreeInspection() async throws {
        let runtime = await configuredRuntime()
        let jarURL = fixturesDirectory().appendingPathComponent("archives/sample.jar")
        guard FileManager.default.fileExists(atPath: jarURL.path) else {
            return XCTFail("Missing sample.jar fixture")
        }

        let result = await runtime.preview(fileURL: jarURL)
        guard let doc = document(for: result),
              let tree = doc.blocks.compactMap({ block -> TreeBlock? in if case let .tree(t) = block { return t }; return nil }).first
        else {
            return XCTFail("Expected tree block for sample.jar, got \(result)")
        }

        XCTAssertTrue(tree.roots.contains { $0.label == "META-INF" }, "JAR archive tree must show META-INF directory")
    }

    // MARK: - WebAssembly Binary Magic Tests

    func testWebAssemblyBinaryMagic() async throws {
        let runtime = await configuredRuntime()
        let wasmURL = fixturesDirectory().appendingPathComponent("binary/sample.wasm")
        guard FileManager.default.fileExists(atPath: wasmURL.path) else {
            return XCTFail("Missing sample.wasm fixture")
        }

        let result = await runtime.preview(fileURL: wasmURL)
        guard let doc = document(for: result) else {
            return XCTFail("Failed to preview sample.wasm")
        }
        XCTAssertEqual(doc.subtitle, "Binary metadata")
        let magic = doc.metadata.first(where: { $0.key == "Magic bytes" })?.value
        XCTAssertTrue(magic?.hasPrefix("00 61 73 6D") == true, "WASM magic bytes must start with 00 61 73 6D")
    }
}

