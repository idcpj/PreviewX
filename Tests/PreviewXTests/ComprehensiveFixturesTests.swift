import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import PreviewXCore
@testable import PreviewXProviders

/// Comprehensive test suite covering the unified fixtures corpus in `Tests/Fixtures`.
/// Validates normal parsing, malformed handling, Git diff highlighting, security detection,
/// archive traversal warnings, and resource budget boundaries.
final class ComprehensiveFixturesTests: XCTestCase {
    private func fixturesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // PreviewXTests
            .deletingLastPathComponent() // Tests
            .appendingPathComponent("Fixtures", isDirectory: true)
    }

    private func configuredRuntime() async -> PreviewRuntime {
        let registry = ProviderRegistry()
        let runtime = PreviewRuntime(registry: registry)
        try? await BuiltInProviders.registerAll(into: registry)
        return runtime
    }

    // MARK: - Git Diff and Patch Tests

    func testGitDiffFixturesHighlightAndClassifyAsDiff() async throws {
        let runtime = await configuredRuntime()
        let diffURL = fixturesDirectory().appendingPathComponent("diff/sample.diff")
        let patchURL = fixturesDirectory().appendingPathComponent("diff/sample.patch")

        for file in [diffURL, patchURL] {
            guard FileManager.default.fileExists(atPath: file.path) else {
                XCTFail("Missing fixture: \(file.path)")
                continue
            }
            let result = await runtime.preview(fileURL: file)
            guard case let .success(document) = result else {
                XCTFail("Expected success preview for \(file.lastPathComponent), got \(result)")
                continue
            }
            XCTAssertEqual(document.subtitle, "Diff")
            XCTAssertEqual(document.metadata.first(where: { $0.key == "Language" })?.value, "Diff")

            // Verify tokens are emitted and diff line coloring is active
            guard case let .code(codeBlock)? = document.blocks.first(where: { if case .code = $0 { return true }; return false }) else {
                XCTFail("Expected code block for \(file.lastPathComponent)")
                continue
            }

            let lines = codeBlock.content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var foundAddition = false
            var foundDeletion = false
            var foundHunk = false
            var foundHeader = false

            for line in lines {
                let tokens = SyntaxHighlighter.tokens(in: line, language: "diff")
                XCTAssertEqual(tokens.map(\.text).joined(), line, "Tokens must faithfully reconstruct line: \(line)")
                if line.hasPrefix("+") && !line.hasPrefix("+++") {
                    XCTAssertEqual(tokens.first?.kind, .string, "Additions should use string (green) token")
                    foundAddition = true
                } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                    XCTAssertEqual(tokens.first?.kind, .attribute, "Deletions should use attribute (pink) token")
                    foundDeletion = true
                } else if line.hasPrefix("@@") {
                    XCTAssertEqual(tokens.first?.kind, .keyword, "Hunks should use keyword token")
                    foundHunk = true
                } else if line.hasPrefix("diff --git") || line.hasPrefix("---") || line.hasPrefix("+++") {
                    XCTAssertEqual(tokens.first?.kind, .comment, "Headers should use comment token")
                    foundHeader = true
                }
            }

            XCTAssertTrue(foundAddition, "Expected diff additions in \(file.lastPathComponent)")
            XCTAssertTrue(foundDeletion, "Expected diff deletions in \(file.lastPathComponent)")
            XCTAssertTrue(foundHunk, "Expected diff hunks in \(file.lastPathComponent)")
            XCTAssertTrue(foundHeader, "Expected diff headers in \(file.lastPathComponent)")
        }
    }

    // MARK: - Malformed Fixtures Tests

    func testMalformedJSONFixturesProduceMalformedWarning() async throws {
        let runtime = await configuredRuntime()
        let malformedDir = fixturesDirectory().appendingPathComponent("malformed", isDirectory: true)
        let jsonFiles = ["invalid.json", "trailing_comma.json", "unclosed_bracket.json", "unquoted_key.json"]

        for filename in jsonFiles {
            let file = malformedDir.appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }

            let result = await runtime.preview(fileURL: file)
            guard case let .partial(document, warnings) = result else {
                XCTFail("Expected partial result with malformed warnings for \(filename), got \(result)")
                continue
            }
            XCTAssertTrue(
                warnings.contains { $0.kind == .malformed },
                "Expected malformed warning for \(filename)"
            )
            XCTAssertTrue(
                document.subtitle?.localizedCaseInsensitiveContains("malformed") ?? false,
                "Subtitle should indicate malformed for \(filename)"
            )
            XCTAssertTrue(
                document.blocks.contains { if case .error = $0 { return true }; return false },
                "Expected error block for \(filename)"
            )
        }
    }

    func testMalformedYAMLFixturesEmitWarnings() async throws {
        let runtime = await configuredRuntime()
        let malformedDir = fixturesDirectory().appendingPathComponent("malformed", isDirectory: true)
        let tabFile = malformedDir.appendingPathComponent("invalid_tab.yaml")

        if FileManager.default.fileExists(atPath: tabFile.path) {
            let result = await runtime.preview(fileURL: tabFile)
            guard case let .partial(document, warnings) = result else {
                return XCTFail("Expected partial result for invalid_tab.yaml, got \(result)")
            }
            XCTAssertFalse(warnings.isEmpty, "Expected warning for tab indentation in YAML")
            XCTAssertFalse(document.blocks.isEmpty)
        }
    }

    func testMalformedTOMLFixturesEmitMalformedWarnings() async throws {
        let runtime = await configuredRuntime()
        let malformedDir = fixturesDirectory().appendingPathComponent("malformed", isDirectory: true)
        let file = malformedDir.appendingPathComponent("invalid_syntax.toml")

        if FileManager.default.fileExists(atPath: file.path) {
            let result = await runtime.preview(fileURL: file)
            guard case let .partial(document, warnings) = result else {
                return XCTFail("Expected partial result for invalid_syntax.toml, got \(result)")
            }
            XCTAssertTrue(warnings.contains { $0.kind == .malformed })
            XCTAssertFalse(document.blocks.isEmpty)
        }
    }

    func testMalformedXMLFixturesEmitMalformedWarnings() async throws {
        let runtime = await configuredRuntime()
        let malformedDir = fixturesDirectory().appendingPathComponent("malformed", isDirectory: true)
        let unclosed = malformedDir.appendingPathComponent("unclosed_tag.xml")
        let mismatched = malformedDir.appendingPathComponent("mismatched_tags.xml")

        for file in [unclosed, mismatched] {
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            let result = await runtime.preview(fileURL: file)
            guard case let .partial(document, warnings) = result else {
                XCTFail("Expected partial result for \(file.lastPathComponent), got \(result)")
                continue
            }
            XCTAssertTrue(warnings.contains { $0.kind == .malformed })
            XCTAssertTrue(document.subtitle?.localizedCaseInsensitiveContains("malformed") ?? false)
            XCTAssertTrue(document.blocks.contains { if case .error = $0 { return true }; return false })
        }
    }

    func testMalformedCSVFixturesEmitMalformedWarning() async throws {
        let runtime = await configuredRuntime()
        let malformedDir = fixturesDirectory().appendingPathComponent("malformed", isDirectory: true)
        let file = malformedDir.appendingPathComponent("unclosed_quote.csv")

        if FileManager.default.fileExists(atPath: file.path) {
            let result = await runtime.preview(fileURL: file)
            guard case let .partial(document, warnings) = result else {
                return XCTFail("Expected partial result for unclosed_quote.csv, got \(result)")
            }
            XCTAssertTrue(warnings.contains { $0.kind == .malformed })
            XCTAssertFalse(document.blocks.isEmpty)
        }
    }

    // MARK: - Security Fixtures Tests

    func testSecurityFixturesTriggerSecretDetection() async throws {
        let runtime = await configuredRuntime()
        let secDir = fixturesDirectory().appendingPathComponent("security", isDirectory: true)
        let envFile = secDir.appendingPathComponent("secret_keys.env")
        let pemFile = secDir.appendingPathComponent("private_key.pem")

        for file in [envFile, pemFile] {
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            let result = await runtime.preview(fileURL: file)
            guard case let .partial(_, warnings) = result else {
                XCTFail("Expected partial preview with security warning for \(file.lastPathComponent), got \(result)")
                continue
            }
            XCTAssertTrue(warnings.contains { $0.kind == .security }, "Expected security warning for \(file.lastPathComponent)")
        }
    }

    // MARK: - Archive Traversal Tests

    func testArchiveTraversalFixturesMarkUnsafe() async throws {
        let runtime = await configuredRuntime()
        let archivesDir = fixturesDirectory().appendingPathComponent("archives", isDirectory: true)
        let zipFile = archivesDir.appendingPathComponent("unsafe_traversal.zip")

        if FileManager.default.fileExists(atPath: zipFile.path) {
            let result = await runtime.preview(fileURL: zipFile)
            guard case let .partial(document, warnings) = result else {
                return XCTFail("Expected partial preview for unsafe_traversal.zip, got \(result)")
            }
            XCTAssertTrue(warnings.contains { $0.kind == .security })
            let trees = document.blocks.compactMap { block -> TreeBlock? in
                if case let .tree(tree) = block { return tree }
                return nil
            }
            func hasUnsafe(_ node: TreeNode) -> Bool {
                node.isUnsafe || node.children.contains(where: hasUnsafe)
            }
            XCTAssertTrue(trees.flatMap(\.roots).contains(where: hasUnsafe))
        }
    }

    // MARK: - Binary Fixtures Tests

    func testBinaryFixturesRenderHexTable() async throws {
        let runtime = await configuredRuntime()
        let binDir = fixturesDirectory().appendingPathComponent("binary", isDirectory: true)
        let macho = binDir.appendingPathComponent("sample_macho.bin")

        if FileManager.default.fileExists(atPath: macho.path) {
            let result = await runtime.preview(fileURL: macho)
            guard case let .partial(document, _) = result else {
                return XCTFail("Expected binary metadata result, got \(result)")
            }
            XCTAssertEqual(document.subtitle, "Binary metadata")
            guard case let .table(table)? = document.blocks.first(where: { if case .table = $0 { return true }; return false }) else {
                return XCTFail("Expected table block in binary preview")
            }
            XCTAssertFalse(table.rows.isEmpty)
        }
    }

    // MARK: - Huge & Budget Boundary Tests

    func testHugeFixturesTriggerTruncationOrRejection() async throws {
        let runtime = await configuredRuntime()
        let hugeDir = fixturesDirectory().appendingPathComponent("huge", isDirectory: true)
        let largeText = hugeDir.appendingPathComponent("large_text.txt")
        let largeCSV = hugeDir.appendingPathComponent("large_table.csv")
        let exceedBudget = hugeDir.appendingPathComponent("exceed_budget.bin")

        // 1. Line budget truncation
        if FileManager.default.fileExists(atPath: largeText.path) {
            let result = await runtime.preview(fileURL: largeText)
            guard case let .partial(_, warnings) = result else {
                return XCTFail("Expected partial preview for large_text.txt, got \(result)")
            }
            XCTAssertTrue(warnings.contains { $0.kind == .truncated })
        }

        // 2. CSV row budget truncation
        if FileManager.default.fileExists(atPath: largeCSV.path) {
            let result = await runtime.preview(fileURL: largeCSV)
            guard case let .partial(_, warnings) = result else {
                return XCTFail("Expected partial preview for large_table.csv, got \(result)")
            }
            XCTAssertTrue(warnings.contains { $0.kind == .truncated })
        }

        // 3. Exceed byte budget bounds and rejection
        if FileManager.default.fileExists(atPath: exceedBudget.path) {
            // Default policy: safely bounded to 512 bytes, avoids OOM
            let defaultResult = await runtime.preview(fileURL: exceedBudget)
            guard case let .partial(document, _) = defaultResult else {
                return XCTFail("Expected bounded preview for exceed_budget.bin, got \(defaultResult)")
            }
            XCTAssertEqual(document.metadata.first(where: { $0.key == "Read" })?.value, "512 bytes")

            // Constrained budget (< 512 bytes): fails with .tooLarge
            var strictPolicy = PreviewPolicy.default
            strictPolicy.budget.maxBytesRead = 256
            let strictResult = await runtime.preview(fileURL: exceedBudget, policy: strictPolicy)
            guard case let .failed(error) = strictResult else {
                return XCTFail("Expected strict budget failure for exceed_budget.bin, got \(strictResult)")
            }
            XCTAssertEqual(error.reason, .tooLarge)
        }
    }

    // MARK: - Database Tests

    func testDatabaseFixturesParseHeader() async throws {
        let runtime = await configuredRuntime()
        let dbDir = fixturesDirectory().appendingPathComponent("database", isDirectory: true)
        let validDB = dbDir.appendingPathComponent("sample.sqlite")

        if FileManager.default.fileExists(atPath: validDB.path) {
            let result = await runtime.preview(fileURL: validDB)
            guard case let .success(document) = result else {
                return XCTFail("Expected SQLite metadata, got \(result)")
            }
            XCTAssertEqual(document.subtitle, "SQLite metadata")
        }
    }

    // MARK: - Specialized Archive Tests (JAR, TGZ, GZIP Text, Empty ZIP, Unsafe TAR)

    func testJarArchiveSpecializedPreviewWithManifest() async throws {
        let runtime = await configuredRuntime()
        let jarURL = fixturesDirectory().appendingPathComponent("archives/sample.jar")
        guard FileManager.default.fileExists(atPath: jarURL.path) else {
            return XCTFail("Missing sample.jar fixture")
        }

        let result = await runtime.preview(fileURL: jarURL)
        guard case let .success(document) = result else {
            return XCTFail("Expected success preview for sample.jar, got \(result)")
        }

        // Must specialize as "JAR archive"
        XCTAssertEqual(document.subtitle, "JAR archive")

        // Must contain tree block with META-INF and MANIFEST.MF
        guard let tree = document.blocks.compactMap({ block -> TreeBlock? in
            if case let .tree(t) = block { return t }
            return nil
        }).first else {
            return XCTFail("Expected tree block for sample.jar")
        }
        XCTAssertTrue(tree.roots.contains { $0.label == "META-INF" })

        // Must parse MANIFEST.MF and surface attributes in metadata
        let metadataMap = Dictionary(uniqueKeysWithValues: document.metadata.map { ($0.key, $0.value) })
        XCTAssertEqual(metadataMap["Manifest-Version"], "1.0")
        XCTAssertEqual(metadataMap["Created-By"], "PreviewX")
        XCTAssertNotNil(metadataMap["Central directory"])
    }

    func testCompressedTGZArchiveTreePreview() async throws {
        let runtime = await configuredRuntime()
        let tgzURL = fixturesDirectory().appendingPathComponent("archives/sample.tgz")
        guard FileManager.default.fileExists(atPath: tgzURL.path) else {
            return XCTFail("Missing sample.tgz fixture")
        }

        let result = await runtime.preview(fileURL: tgzURL)
        guard case let .success(document) = result else {
            return XCTFail("Expected success preview for sample.tgz, got \(result)")
        }

        XCTAssertEqual(document.subtitle, "TAR.GZ archive")
        guard let tree = document.blocks.compactMap({ block -> TreeBlock? in
            if case let .tree(t) = block { return t }
            return nil
        }).first else {
            return XCTFail("Expected tree block for sample.tgz")
        }
        XCTAssertFalse(tree.roots.isEmpty)
        XCTAssertTrue(document.metadata.contains { $0.key == "Uncompressed" })
        XCTAssertTrue(document.metadata.contains { $0.key == "Compression ratio" })
    }

    func testGzipDecompressedTextPreview() async throws {
        let runtime = await configuredRuntime()
        let txtGzURL = fixturesDirectory().appendingPathComponent("archives/sample.txt.gz")
        guard FileManager.default.fileExists(atPath: txtGzURL.path) else {
            return XCTFail("Missing sample.txt.gz fixture")
        }

        let result = await runtime.preview(fileURL: txtGzURL)
        guard case let .success(document) = result else {
            return XCTFail("Expected success preview for sample.txt.gz, got \(result)")
        }

        XCTAssertEqual(document.subtitle, "GZIP (decompressed)")
        guard let codeBlock = document.blocks.compactMap({ block -> CodeBlock? in
            if case let .code(c) = block { return c }
            return nil
        }).first else {
            return XCTFail("Expected decompressed code block for sample.txt.gz")
        }
        XCTAssertFalse(codeBlock.content.isEmpty)
        XCTAssertTrue(document.metadata.contains { $0.key == "Inflated bytes" })
    }

    func testEmptyZipSafePreview() async throws {
        let runtime = await configuredRuntime()
        let emptyZip = fixturesDirectory().appendingPathComponent("archives/empty.zip")
        guard FileManager.default.fileExists(atPath: emptyZip.path) else {
            return XCTFail("Missing empty.zip fixture")
        }

        let result = await runtime.preview(fileURL: emptyZip)
        guard case let .success(document) = result else {
            return XCTFail("Expected graceful success preview for empty.zip, got \(result)")
        }

        XCTAssertEqual(document.subtitle, "ZIP archive")
        XCTAssertTrue(document.blocks.contains { if case .error = $0 { return true }; return false })
    }

    func testTarArchiveTraversalUnsafeWarning() async throws {
        let runtime = await configuredRuntime()
        let unsafeTar = fixturesDirectory().appendingPathComponent("archives/unsafe_traversal.tar")
        guard FileManager.default.fileExists(atPath: unsafeTar.path) else {
            return XCTFail("Missing unsafe_traversal.tar fixture")
        }

        let result = await runtime.preview(fileURL: unsafeTar)
        guard case let .partial(document, warnings) = result else {
            return XCTFail("Expected partial preview with warnings for unsafe_traversal.tar, got \(result)")
        }

        XCTAssertTrue(warnings.contains { $0.kind == .security })
        guard let tree = document.blocks.compactMap({ block -> TreeBlock? in
            if case let .tree(t) = block { return t }
            return nil
        }).first else {
            return XCTFail("Expected tree block for unsafe_traversal.tar")
        }

        func hasUnsafeNode(_ node: TreeNode) -> Bool {
            node.isUnsafe || node.children.contains(where: hasUnsafeNode)
        }
        XCTAssertTrue(tree.roots.contains(where: hasUnsafeNode), "Tree must mark unsafe traversal path")
    }

    // MARK: - Frontend Components (Vue, Svelte) & Build Code (CMake) Tests

    func testVueAndSvelteComponentsRouteToSourceCode() async throws {
        let runtime = await configuredRuntime()
        let vueURL = fixturesDirectory().appendingPathComponent("code/sample.vue")
        let svelteURL = fixturesDirectory().appendingPathComponent("code/sample.svelte")

        for (fileURL, expectedLang) in [(vueURL, "Vue"), (svelteURL, "Svelte")] {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                XCTFail("Missing fixture: \(fileURL.lastPathComponent)")
                continue
            }

            let result = await runtime.preview(fileURL: fileURL)
            guard case let .success(document) = result else {
                XCTFail("Expected success code preview for \(fileURL.lastPathComponent), got \(result)")
                continue
            }

            XCTAssertEqual(document.subtitle, expectedLang, "Must route to Source Code as \(expectedLang)")
            XCTAssertFalse(document.subtitle?.localizedCaseInsensitiveContains("xml") == true, "Must not misclassify as XML")
            XCTAssertFalse(document.blocks.contains { if case .error = $0 { return true }; return false })

            guard let codeBlock = document.blocks.compactMap({ block -> CodeBlock? in
                if case let .code(c) = block { return c }
                return nil
            }).first else {
                XCTFail("Expected code block for \(fileURL.lastPathComponent)")
                continue
            }

            // Verify syntax tokens reconstruct lines
            for line in codeBlock.content.split(separator: "\n").map(String.init) {
                let tokens = SyntaxHighlighter.tokens(in: line, language: expectedLang.lowercased())
                XCTAssertEqual(tokens.map(\.text).joined(), line)
            }
        }
    }

    func testCMakeSyntaxHighlighting() async throws {
        let runtime = await configuredRuntime()
        let cmakeURL = fixturesDirectory().appendingPathComponent("code/CMakeLists.txt")
        guard FileManager.default.fileExists(atPath: cmakeURL.path) else {
            return XCTFail("Missing CMakeLists.txt fixture")
        }

        let result = await runtime.preview(fileURL: cmakeURL)
        guard case let .success(document) = result else {
            return XCTFail("Expected success preview for CMakeLists.txt, got \(result)")
        }

        XCTAssertEqual(document.subtitle, "CMake")
        guard let codeBlock = document.blocks.compactMap({ block -> CodeBlock? in
            if case let .code(c) = block { return c }
            return nil
        }).first else {
            return XCTFail("Expected code block for CMakeLists.txt")
        }

        XCTAssertTrue(codeBlock.content.contains("cmake_minimum_required"))
        XCTAssertTrue(codeBlock.content.contains("project"))

        let tokens = SyntaxHighlighter.tokens(in: "project(PreviewX C)", language: "cmake")
        XCTAssertTrue(tokens.contains { $0.kind == .keyword && $0.text == "project" })
    }

    // MARK: - Binary Format Specialized Headers (ELF, Mach-O, WASM, Zeroes)

    func testBinarySpecializedHeadersELFAndMachOAndWasm() async throws {
        let runtime = await configuredRuntime()
        let binDir = fixturesDirectory().appendingPathComponent("binary", isDirectory: true)

        // 1. ELF
        let elfURL = binDir.appendingPathComponent("sample_elf.bin")
        if FileManager.default.fileExists(atPath: elfURL.path) {
            let result = await runtime.preview(fileURL: elfURL)
            guard case let .partial(document, _) = result else {
                return XCTFail("Expected binary preview for sample_elf.bin, got \(result)")
            }
            let metaMap = Dictionary(uniqueKeysWithValues: document.metadata.map { ($0.key, $0.value) })
            XCTAssertTrue(metaMap["Format"]?.contains("ELF") == true, "Expected ELF format in metadata: \(metaMap)")
            XCTAssertEqual(metaMap["ELF type"], "Executable")
            XCTAssertTrue(metaMap["Magic bytes"]?.starts(with: "7F 45 4C 46") == true)
        }

        // 2. Mach-O
        let machoURL = binDir.appendingPathComponent("sample_macho.bin")
        if FileManager.default.fileExists(atPath: machoURL.path) {
            let result = await runtime.preview(fileURL: machoURL)
            guard case let .partial(document, _) = result else {
                return XCTFail("Expected binary preview for sample_macho.bin, got \(result)")
            }
            let metaMap = Dictionary(uniqueKeysWithValues: document.metadata.map { ($0.key, $0.value) })
            XCTAssertTrue(metaMap["Format"]?.contains("Mach-O") == true)
        }

        // 3. WebAssembly
        let wasmURL = binDir.appendingPathComponent("sample.wasm")
        if FileManager.default.fileExists(atPath: wasmURL.path) {
            let result = await runtime.preview(fileURL: wasmURL)
            guard case let .partial(document, _) = result else {
                return XCTFail("Expected binary preview for sample.wasm, got \(result)")
            }
            let metaMap = Dictionary(uniqueKeysWithValues: document.metadata.map { ($0.key, $0.value) })
            XCTAssertTrue(metaMap["Format"]?.contains("WebAssembly") == true)
            XCTAssertTrue(metaMap["Magic bytes"]?.starts(with: "00 61 73 6D") == true)
        }

        // 4. Sample Zeroes
        let zeroesURL = binDir.appendingPathComponent("sample_zeroes.bin")
        if FileManager.default.fileExists(atPath: zeroesURL.path) {
            let result = await runtime.preview(fileURL: zeroesURL)
            guard case let .partial(document, _) = result else {
                return XCTFail("Expected binary preview for sample_zeroes.bin, got \(result)")
            }
            XCTAssertEqual(document.subtitle, "Binary metadata")
            XCTAssertFalse(document.blocks.isEmpty)
        }
    }

    // MARK: - Security Token Detection Tests

    func testJSONAuthorizationTokenSecretDetection() async throws {
        let runtime = await configuredRuntime()
        let tokenURL = fixturesDirectory().appendingPathComponent("security/authorization_token.json")
        guard FileManager.default.fileExists(atPath: tokenURL.path) else {
            return XCTFail("Missing authorization_token.json fixture")
        }

        let result = await runtime.preview(fileURL: tokenURL)
        guard case let .partial(document, warnings) = result else {
            return XCTFail("Expected partial preview with security warning for authorization_token.json, got \(result)")
        }

        XCTAssertTrue(warnings.contains { $0.kind == .security }, "Must trigger security warning for JWT / Bearer token in JSON")
        XCTAssertEqual(document.subtitle, "JSON")
    }

    // MARK: - Multi-File Diff, Complex CSV, SVG, POM, YAML, Unicode CRLF Tests

    func testMultiFileDiffSyntaxHighlighting() async throws {
        let runtime = await configuredRuntime()
        let diffURL = fixturesDirectory().appendingPathComponent("diff/multi_file.diff")
        guard FileManager.default.fileExists(atPath: diffURL.path) else {
            return XCTFail("Missing multi_file.diff fixture")
        }

        let result = await runtime.preview(fileURL: diffURL)
        guard case let .success(document) = result else {
            return XCTFail("Expected success preview for multi_file.diff, got \(result)")
        }

        XCTAssertEqual(document.subtitle, "Diff")
        guard let codeBlock = document.blocks.compactMap({ block -> CodeBlock? in
            if case let .code(c) = block { return c }
            return nil
        }).first else {
            return XCTFail("Expected code block for multi_file.diff")
        }

        XCTAssertTrue(codeBlock.content.contains("diff --git a/Package.swift b/Package.swift"))
        XCTAssertTrue(codeBlock.content.contains("diff --git a/README.md b/README.md"))
    }

    func testComplexQuotedCSVTablePreview() async throws {
        let runtime = await configuredRuntime()
        let csvURL = fixturesDirectory().appendingPathComponent("csv/complex_quoted.csv")
        guard FileManager.default.fileExists(atPath: csvURL.path) else {
            return XCTFail("Missing complex_quoted.csv fixture")
        }

        let result = await runtime.preview(fileURL: csvURL)
        guard case let .success(document) = result else {
            return XCTFail("Expected success preview for complex_quoted.csv, got \(result)")
        }

        XCTAssertEqual(document.subtitle, "CSV")
        guard let table = document.blocks.compactMap({ block -> TableBlock? in
            if case let .table(t) = block { return t }
            return nil
        }).first else {
            return XCTFail("Expected table block for complex_quoted.csv")
        }

        XCTAssertFalse(table.columns.isEmpty)
        XCTAssertFalse(table.rows.isEmpty)
    }

    func testSVGAndPomXMLPreview() async throws {
        let runtime = await configuredRuntime()
        let svgURL = fixturesDirectory().appendingPathComponent("xml/sample.svg")
        let pomURL = fixturesDirectory().appendingPathComponent("xml/pom.xml")

        for fileURL in [svgURL, pomURL] {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            let result = await runtime.preview(fileURL: fileURL)
            guard case let .success(document) = result else {
                XCTFail("Expected success preview for \(fileURL.lastPathComponent), got \(result)")
                continue
            }
            XCTAssertEqual(document.subtitle, "XML")
            XCTAssertTrue(document.blocks.contains { if case .code = $0 { return true }; return false })
        }
    }

    func testDockerComposeAndK8sYAMLPreview() async throws {
        let runtime = await configuredRuntime()
        let composeURL = fixturesDirectory().appendingPathComponent("yaml/docker-compose.yml")
        let k8sURL = fixturesDirectory().appendingPathComponent("yaml/k8s-pod.yaml")

        for fileURL in [composeURL, k8sURL] {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            let result = await runtime.preview(fileURL: fileURL)
            guard case let .success(document) = result else {
                XCTFail("Expected success preview for \(fileURL.lastPathComponent), got \(result)")
                continue
            }
            XCTAssertEqual(document.subtitle, "YAML")
            XCTAssertTrue(document.blocks.contains { if case .code = $0 { return true }; return false })
        }
    }

    func testWindowsCRLFAndMixedUnicodeTextPreview() async throws {
        let runtime = await configuredRuntime()
        let crlfURL = fixturesDirectory().appendingPathComponent("text/crlf_sample.txt")
        let mixedURL = fixturesDirectory().appendingPathComponent("unicode/mixed.txt")

        for fileURL in [crlfURL, mixedURL] {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            let result = await runtime.preview(fileURL: fileURL)
            guard case let .success(document) = result else {
                XCTFail("Expected success preview for \(fileURL.lastPathComponent), got \(result)")
                continue
            }
            XCTAssertEqual(document.subtitle, "Plain text")
            XCTAssertTrue(document.blocks.contains { if case .text = $0 { return true }; return false })
        }
    }

    // MARK: - Markdown Specialized Preview & Anti-Plaintext Routing Tests

    func testAdvancedMarkdownFixtureRendersAsMarkdownNotPlainText() async throws {
        let runtime = await configuredRuntime()
        let advancedURL = fixturesDirectory().appendingPathComponent("text/advanced.md")
        guard FileManager.default.fileExists(atPath: advancedURL.path) else {
            XCTFail("Missing fixture: \(advancedURL.path)")
            return
        }

        let result = await runtime.preview(fileURL: advancedURL)
        guard case let .success(document) = result else {
            XCTFail("Expected success preview for advanced.md, got \(result)")
            return
        }

        // 1. Must NOT be plain text
        XCTAssertNotEqual(document.subtitle, "Plain text", "advanced.md must not be previewed as Plain text")
        XCTAssertEqual(document.subtitle, "Markdown", "advanced.md subtitle must be 'Markdown'")

        let providerName = document.metadata.first(where: { $0.key == "Provider" })?.value
        XCTAssertEqual(providerName, "Markdown", "Provider must be Markdown")

        // 2. Must contain .markdown block, not solely .text
        let markdownBlocks = document.blocks.compactMap { block -> MarkdownBlock? in
            if case let .markdown(mb) = block { return mb }
            return nil
        }
        XCTAssertFalse(markdownBlocks.isEmpty, "advanced.md must contain a MarkdownBlock")
        guard let markdownBlock = markdownBlocks.first else { return }

        // 3. Structural validation of nodes
        let nodes = markdownBlock.nodes
        XCTAssertFalse(nodes.isEmpty, "Markdown block should have parsed nodes")

        // Heading 1: PreviewX Extended Markdown
        let h1 = nodes.first(where: { $0.kind == .heading && $0.level == 1 })
        XCTAssertNotNil(h1, "Must contain H1 heading")
        XCTAssertEqual(h1?.text, "PreviewX Extended Markdown")

        // Paragraph: A local-first, safe preview tool for macOS.
        let paragraph = nodes.first(where: { $0.kind == .paragraph })
        XCTAssertNotNil(paragraph, "Must contain paragraph")
        XCTAssertTrue(paragraph?.text.contains("local-first") ?? false)

        // Heading 2: Feature Checklist
        let h2 = nodes.first(where: { $0.kind == .heading && $0.level == 2 })
        XCTAssertNotNil(h2, "Must contain H2 heading")
        XCTAssertEqual(h2?.text, "Feature Checklist")

        // Task Items: 4 items, all checked ([x])
        let taskItems = nodes.filter { $0.kind == .taskItem }
        XCTAssertEqual(taskItems.count, 4, "Must parse exactly 4 task items")
        for item in taskItems {
            XCTAssertEqual(item.isDone, true, "Task item '\(item.text)' must have isDone == true")
        }
        let taskTexts = taskItems.map(\.text)
        XCTAssertTrue(taskTexts.contains("Fast Quick Look"))
        XCTAssertTrue(taskTexts.contains("Syntax Highlighting"))
        XCTAssertTrue(taskTexts.contains("Unified Diff Viewer"))
        XCTAssertTrue(taskTexts.contains("Secret Redaction"))

        // Quote: Preview first, open later.
        let quote = nodes.first(where: { $0.kind == .quote })
        XCTAssertNotNil(quote, "Must contain quote")
        XCTAssertTrue(quote?.text.contains("Preview first, open later.") ?? false)

        // CodeBlock: Swift code block
        let codeBlock = nodes.first(where: { $0.kind == .codeBlock })
        XCTAssertNotNil(codeBlock, "Must contain code block")
        XCTAssertEqual(codeBlock?.language?.lowercased(), "swift")
        XCTAssertTrue(codeBlock?.text.contains("func greet()") ?? false)
    }

    func testMarkdownPreemptsPlainTextEvenWhenDeclaredAsPlainTextType() async throws {
        let registry = ProviderRegistry()
        try await BuiltInProviders.registerAll(into: registry)

        // Simulate an OS environment where the file is reported as public.plain-text
        let tempURL = URL(fileURLWithPath: "/tmp/sample_doc.md")
        let identity = FileIdentity(
            url: tempURL,
            filename: "sample_doc.md",
            size: 100,
            contentTypeIdentifier: "public.plain-text"
        )
        let classification = FileClassification(
            contentTypeIdentifier: "public.plain-text",
            filenameExtension: "md",
            signatures: ["text"],
            confidence: 0.9,
            evidence: []
        )
        let request = PreviewRequest(
            identity: identity,
            classification: classification,
            deadline: Date().addingTimeInterval(5)
        )

        // Query both providers directly
        let textProvider = TextProvider()
        let markdownProvider = MarkdownProvider()

        let textMatch = await textProvider.canPreview(request)
        let mdMatch = await markdownProvider.canPreview(request)

        // TextProvider MUST NOT preempt MarkdownProvider for .md extension
        XCTAssertEqual(textMatch.confidence, 0, "TextProvider should reject .md files even if classification says plain-text")
        XCTAssertGreaterThan(mdMatch.confidence, 0, "MarkdownProvider must match .md files")
    }

    func testLanguageCatalogIdentifiesMarkdown() {
        let mdURL = URL(fileURLWithPath: "/path/to/document.md")
        let markdownURL = URL(fileURLWithPath: "/path/to/spec.markdown")
        let mdownURL = URL(fileURLWithPath: "/path/to/notes.mdown")

        for url in [mdURL, markdownURL, mdownURL] {
            let definition = LanguageCatalog.definition(for: url)
            XCTAssertNotNil(definition, "LanguageCatalog should identify \(url.lastPathComponent)")
            XCTAssertEqual(definition?.id, "markdown", "\(url.lastPathComponent) must be identified as markdown language")
            XCTAssertEqual(definition?.displayName, "Markdown")
        }
    }

    func testQuickLookExtensionPlistDeclaresMarkdownSupport() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // PreviewXTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // Repository root
        let plistURL = repoRoot.appendingPathComponent("QuickLookExtension/Info.plist")

        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            XCTFail("QuickLookExtension/Info.plist not found at \(plistURL.path)")
            return
        }

        let data = try Data(contentsOf: plistURL)
        let propertyList = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        let nsExtension = propertyList?["NSExtension"] as? [String: Any]
        let attributes = nsExtension?["NSExtensionAttributes"] as? [String: Any]
        let supportedTypes = attributes?["QLSupportedContentTypes"] as? [String] ?? []

        XCTAssertTrue(
            supportedTypes.contains("net.daringfireball.markdown"),
            "QuickLookExtension/Info.plist must declare net.daringfireball.markdown in QLSupportedContentTypes"
        )
        XCTAssertTrue(
            supportedTypes.contains("com.previewx.markdown"),
            "QuickLookExtension/Info.plist must declare com.previewx.markdown in QLSupportedContentTypes"
        )
    }

    func testMarkdownPresentationExcludesOutlineTree() async throws {
        let runtime = await configuredRuntime()
        let sampleURL = fixturesDirectory().appendingPathComponent("text/sample.md")
        let advancedURL = fixturesDirectory().appendingPathComponent("text/advanced.md")

        for fileURL in [sampleURL, advancedURL] {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            let result = await runtime.preview(fileURL: fileURL)
            guard case let .success(document) = result else {
                XCTFail("Expected success preview for \(fileURL.lastPathComponent), got \(result)")
                continue
            }

            // In presentation blocks on macOS, the Outline tree must NOT be displayed
            let presentationBlocks = document.presentationBlocks
            let outlineBlocks = presentationBlocks.compactMap { block -> TreeBlock? in
                if case let .tree(tree) = block, tree.title.localizedCaseInsensitiveContains("outline") {
                    return tree
                }
                return nil
            }
            XCTAssertTrue(
                outlineBlocks.isEmpty,
                "\(fileURL.lastPathComponent) presentationBlocks must NOT contain Outline tree (should purely display markdown)"
            )

            // Presentation blocks should contain the pure markdown block
            let hasMarkdown = presentationBlocks.contains {
                if case .markdown = $0 { return true }
                return false
            }
            XCTAssertTrue(hasMarkdown, "\(fileURL.lastPathComponent) must contain markdown block in presentation")
        }
    }

    func testSampleMarkdownFixtureRendersAsMarkdownFormat() async throws {
        let runtime = await configuredRuntime()
        let advancedURL = fixturesDirectory().appendingPathComponent("text/advanced.md")
        let markdownURL = fixturesDirectory().appendingPathComponent("text/sample.markdown")
        let mdownURL = fixturesDirectory().appendingPathComponent("text/sample.mdown")

        guard FileManager.default.fileExists(atPath: advancedURL.path) else {
            return XCTFail("Missing fixture: \(advancedURL.path)")
        }

        let advancedResult = await runtime.preview(fileURL: advancedURL)
        guard case let .success(advancedDoc) = advancedResult else {
            return XCTFail("Expected success preview for advanced.md, got \(advancedResult)")
        }

        guard let advancedMdBlock = advancedDoc.presentationBlocks.compactMap({ block -> MarkdownBlock? in
            if case let .markdown(mb) = block { return mb }
            return nil
        }).first else {
            return XCTFail("advanced.md must contain MarkdownBlock in presentationBlocks")
        }

        for fileURL in [markdownURL, mdownURL] {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                XCTFail("Missing fixture: \(fileURL.path)")
                continue
            }

            let result = await runtime.preview(fileURL: fileURL)
            guard case let .success(document) = result else {
                XCTFail("Expected success preview for \(fileURL.lastPathComponent), got \(result)")
                continue
            }

            // Subtitle must be Markdown
            XCTAssertEqual(document.subtitle, "Markdown", "\(fileURL.lastPathComponent) subtitle must be 'Markdown'")

            // Provider must be Markdown
            let providerName = document.metadata.first(where: { $0.key == "Provider" })?.value
            XCTAssertEqual(providerName, "Markdown", "\(fileURL.lastPathComponent) provider must be 'Markdown'")

            // Type must be net.daringfireball.markdown
            let type = document.metadata.first(where: { $0.key == "Type" })?.value
            XCTAssertEqual(type, "net.daringfireball.markdown", "\(fileURL.lastPathComponent) Type must be 'net.daringfireball.markdown'")

            // Presentation blocks must NOT contain outline and must contain markdown block
            XCTAssertFalse(
                document.presentationBlocks.contains { if case .tree = $0 { return true }; return false },
                "\(fileURL.lastPathComponent) presentationBlocks must not contain Outline tree"
            )
            guard let mdBlock = document.presentationBlocks.compactMap({ block -> MarkdownBlock? in
                if case let .markdown(mb) = block { return mb }
                return nil
            }).first else {
                XCTFail("\(fileURL.lastPathComponent) must contain MarkdownBlock in presentationBlocks")
                continue
            }

            // Verify equivalent nodes with advanced.md
            XCTAssertEqual(
                mdBlock.nodes.count,
                advancedMdBlock.nodes.count,
                "\(fileURL.lastPathComponent) must have the exact same node count as advanced.md"
            )

            for (index, (node, expectedNode)) in zip(mdBlock.nodes, advancedMdBlock.nodes).enumerated() {
                XCTAssertEqual(node.kind, expectedNode.kind, "Node [\(index)] kind mismatch in \(fileURL.lastPathComponent)")
                XCTAssertEqual(node.level, expectedNode.level, "Node [\(index)] level mismatch in \(fileURL.lastPathComponent)")
                XCTAssertEqual(node.text, expectedNode.text, "Node [\(index)] text mismatch in \(fileURL.lastPathComponent)")
                XCTAssertEqual(node.language, expectedNode.language, "Node [\(index)] language mismatch in \(fileURL.lastPathComponent)")
                XCTAssertEqual(node.isDone, expectedNode.isDone, "Node [\(index)] isDone mismatch in \(fileURL.lastPathComponent)")
            }

            // Explicitly assert key elements from advanced.md
            let nodes = mdBlock.nodes
            XCTAssertTrue(nodes.contains { $0.kind == .heading && $0.level == 1 && $0.text == "PreviewX Extended Markdown" })
            XCTAssertTrue(nodes.contains { $0.kind == .paragraph && $0.text == "A local-first, safe preview tool for macOS." })
            XCTAssertTrue(nodes.contains { $0.kind == .heading && $0.level == 2 && $0.text == "Feature Checklist" })
            XCTAssertTrue(nodes.contains { $0.kind == .taskItem && $0.text == "Fast Quick Look" && $0.isDone == true })
            XCTAssertTrue(nodes.contains { $0.kind == .taskItem && $0.text == "Syntax Highlighting" && $0.isDone == true })
            XCTAssertTrue(nodes.contains { $0.kind == .taskItem && $0.text == "Unified Diff Viewer" && $0.isDone == true })
            XCTAssertTrue(nodes.contains { $0.kind == .taskItem && $0.text == "Secret Redaction" && $0.isDone == true })
            XCTAssertTrue(nodes.contains { $0.kind == .quote && $0.text == "Preview first, open later." })
            XCTAssertTrue(nodes.contains { $0.kind == .codeBlock && $0.language == "swift" })
        }
    }

    func testAppPlistDeclaresMarkdownImportedType() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // PreviewXTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // Repository root
        let plistURL = repoRoot.appendingPathComponent("App/Info.plist")

        let data = try Data(contentsOf: plistURL)
        let propertyList = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        let importedTypes = propertyList?["UTImportedTypeDeclarations"] as? [[String: Any]] ?? []

        let markdownDecl = importedTypes.first { $0["UTTypeIdentifier"] as? String == "net.daringfireball.markdown" }
        XCTAssertNotNil(markdownDecl, "App/Info.plist must declare net.daringfireball.markdown in UTImportedTypeDeclarations")

        let tagSpec = markdownDecl?["UTTypeTagSpecification"] as? [String: Any]
        let exts = tagSpec?["public.filename-extension"] as? [String] ?? []
        XCTAssertTrue(exts.contains("markdown"), "UTImportedTypeDeclarations must include 'markdown' extension")
        XCTAssertTrue(exts.contains("md"), "UTImportedTypeDeclarations must include 'md' extension")
        XCTAssertTrue(exts.contains("mdown"), "UTImportedTypeDeclarations must include 'mdown' extension")

        let exportedTypes = propertyList?["UTExportedTypeDeclarations"] as? [[String: Any]] ?? []
        let exportedMarkdownDecl = exportedTypes.first { $0["UTTypeIdentifier"] as? String == "com.previewx.markdown" }
        XCTAssertNotNil(exportedMarkdownDecl, "App/Info.plist must declare com.previewx.markdown in UTExportedTypeDeclarations")
        let exportedTagSpec = exportedMarkdownDecl?["UTTypeTagSpecification"] as? [String: Any]
        let exportedExts = exportedTagSpec?["public.filename-extension"] as? [String] ?? []
        XCTAssertTrue(exportedExts.contains("markdown"), "UTExportedTypeDeclarations must include 'markdown' extension")
        XCTAssertTrue(exportedExts.contains("mdown"), "UTExportedTypeDeclarations must include 'mdown' extension")
        XCTAssertTrue(exportedExts.contains("md"), "UTExportedTypeDeclarations must include 'md' extension")
    }
}


