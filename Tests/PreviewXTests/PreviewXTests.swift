import Foundation
import XCTest
import zlib
@testable import PreviewXCore
@testable import PreviewXProviders
@testable import PreviewXUI

final class PreviewXTests: XCTestCase {
    func testJSONPreviewUsesSingleFormattedCodeRepresentation() async throws {
        let file = try temporaryFile(named: "payload.bin", contents: Data("{\"name\":\"PreviewX\",\"enabled\":true}".utf8))
        defer { remove(file) }

        let result = await configuredRuntime().preview(fileURL: file)
        guard case let .success(document) = result else {
            return XCTFail("Expected JSON success, got \(result)")
        }

        XCTAssertEqual(document.subtitle, "JSON")
        XCTAssertEqual(document.metadata.first(where: { $0.key == "Provider" })?.value, "JSON")
        XCTAssertEqual(document.blocks.count, 1)
        guard case let .code(block) = document.blocks[0] else {
            return XCTFail("Expected the fixed JSON code representation")
        }
        XCTAssertEqual(block.language, "json")
        XCTAssertEqual(block.content, "{\n  \"enabled\" : true,\n  \"name\" : \"PreviewX\"\n}")
    }

    func testMalformedJSONPreservesRawInput() async throws {
        let content = "{\"items\": [1, 2, }"
        let file = try temporaryFile(named: "invalid.json", contents: Data(content.utf8))
        defer { remove(file) }

        let result = await configuredRuntime().preview(fileURL: file)
        guard case let .partial(document, warnings) = result else {
            return XCTFail("Expected partial JSON result, got \(result)")
        }

        XCTAssertTrue(warnings.contains { $0.kind == .malformed })
        XCTAssertTrue(document.blocks.contains {
            if case let .code(block) = $0 { return block.content == content }
            return false
        })
    }

    func testDataDrivenSourceLanguageRouting() async throws {
        let file = try temporaryFile(named: "main.swift", contents: Data("public func hello() {}".utf8))
        defer { remove(file) }

        let result = await configuredRuntime().preview(fileURL: file)
        guard case let .success(document) = result else {
            return XCTFail("Expected source preview, got \(result)")
        }

        XCTAssertEqual(document.subtitle, "Swift")
        XCTAssertEqual(document.metadata.first(where: { $0.key == "Provider" })?.value, "Source Code")
    }

    func testCSVParsesQuotedFields() async throws {
        let file = try temporaryFile(named: "people.csv", contents: Data("name,notes\nAda,\"writes, tests\"\n".utf8))
        defer { remove(file) }

        let result = await configuredRuntime().preview(fileURL: file)
        guard case let .success(document) = result,
              let table = document.blocks.compactMap({ block -> TableBlock? in if case let .table(value) = block { return value }; return nil }).first
        else {
            return XCTFail("Expected CSV table, got \(result)")
        }

        XCTAssertEqual(table.columns, ["name", "notes"])
        XCTAssertEqual(table.rows.first, ["Ada", "writes, tests"])
    }

    func testLogRendersCleanCodeBlockDirectly() async throws {
        let file = try temporaryFile(named: "service.log", contents: Data("2026-08-16T09:20:31Z INFO server started\n".utf8))
        defer { remove(file) }

        let result = await configuredRuntime().preview(fileURL: file)
        guard case let .success(document) = result,
              let code = document.blocks.compactMap({ block -> CodeBlock? in if case let .code(value) = block { return value }; return nil }).first
        else {
            return XCTFail("Expected log code block, got \(result)")
        }

        XCTAssertEqual(code.language, "log")
        XCTAssertTrue(code.content.contains("2026-08-16T09:20:31Z INFO server started"))
        XCTAssertFalse(document.blocks.contains { if case .table = $0 { return true }; return false })
    }

    func testYAMLTOMLAndXMLProduceFormattedCodeRepresentations() async throws {
        let fixtures: [(String, String, String)] = [
            ("config.yaml", "service:\n  name: previewx\n", "YAML"),
            ("config.toml", "[service]\nname = \"previewx\"\n", "TOML"),
            ("service.xml", "<service><name>previewx</name></service>", "XML")
        ]

        for (name, content, subtitle) in fixtures {
            let file = try temporaryFile(named: name, contents: Data(content.utf8))
            defer { remove(file) }
            let result = await configuredRuntime().preview(fileURL: file)
            guard case let .success(document) = result else {
                return XCTFail("Expected \(subtitle) preview, got \(result)")
            }
            XCTAssertEqual(document.subtitle, subtitle)
            XCTAssertTrue(document.blocks.contains { if case .code = $0 { return true }; return false })
            XCTAssertFalse(document.blocks.contains { if case .tree = $0 { return true }; return false })
        }
    }

    func testMarkdownAndBinaryFallbackPreserveSafeContent() async throws {
        let markdown = try temporaryFile(named: "readme.md", contents: Data("# PreviewX\n\n## Design\n".utf8))
        let binary = try temporaryFile(named: "unknown.bin", contents: Data([0, 1, 2, 255, 0, 3]))
        defer {
            remove(markdown)
            remove(binary)
        }

        let markdownResult = await configuredRuntime().preview(fileURL: markdown)
        guard case let .success(markdownDocument) = markdownResult else {
            return XCTFail("Expected Markdown preview, got \(markdownResult)")
        }
        XCTAssertEqual(markdownDocument.subtitle, "Markdown")
        XCTAssertTrue(markdownDocument.blocks.contains { if case .tree = $0 { return true }; return false })

        let binaryResult = await configuredRuntime().preview(fileURL: binary)
        guard case let .partial(binaryDocument, warnings) = binaryResult else {
            return XCTFail("Expected binary fallback, got \(binaryResult)")
        }
        XCTAssertEqual(binaryDocument.metadata.first(where: { $0.key == "Provider" })?.value, "Binary Metadata")
        XCTAssertTrue(warnings.contains { $0.kind == .unsupportedFeature })
    }

    func testSQLiteHeaderMetadataUsesSignatureNotExtension() async throws {
        var database = Data(repeating: 0, count: 100)
        database.replaceSubrange(0..<16, with: Data("SQLite format 3\0".utf8))
        database[16] = 16
        database[17] = 0
        database[96] = 0
        database[97] = 48
        database[98] = 210
        database[99] = 0
        let file = try temporaryFile(named: "database.data", contents: database)
        defer { remove(file) }

        let result = await configuredRuntime().preview(fileURL: file)
        guard case let .success(document) = result else {
            return XCTFail("Expected SQLite metadata, got \(result)")
        }
        XCTAssertEqual(document.subtitle, "SQLite metadata")
        XCTAssertEqual(document.metadata.first(where: { $0.key == "Provider" })?.value, "SQLite Metadata")
    }

    func testClassificationAndProviderShareReadBudget() async throws {
        let file = try temporaryFile(named: "budget.txt", contents: Data(repeating: 65, count: 12 * 1_024))
        defer { remove(file) }
        let identity = try FileAccess.identity(for: file)
        let budget = ResourceBudget(
            maxBytesRead: 10 * 1_024,
            maxMemoryBytes: 64 * 1_024,
            maxCPUTimeMs: 1_000,
            maxOutputNodes: 100,
            maxArchiveEntries: 100,
            maxTextLines: 20_000
        )
        let tracker = PreviewResourceTracker(maxBytesRead: budget.maxBytesRead)
        let classification = try await FileClassifier().classify(identity: identity, budget: budget, resourceTracker: tracker)
        let request = PreviewRequest(
            identity: identity,
            classification: classification,
            policy: PreviewPolicy(budget: budget),
            resourceTracker: tracker
        )
        let document = try await TextProvider().makePreview(request)

        XCTAssertTrue(document.warnings.contains { $0.kind == .truncated })
        let bytesRead = await tracker.bytesRead()
        XCTAssertEqual(bytesRead, budget.maxBytesRead)
    }

    func testArchiveTraversalIsVisibleAndMarkedUnsafe() async throws {
        let archive = makeZip(entries: [
            ("safe/readme.txt", Data("ok".utf8)),
            ("../escape.txt", Data("never extract".utf8))
        ])
        let file = try temporaryFile(named: "fixture.zip", contents: archive)
        defer { remove(file) }

        let result = await configuredRuntime().preview(fileURL: file)
        guard case let .partial(document, warnings) = result else {
            return XCTFail("Expected partial archive preview, got \(result)")
        }

        XCTAssertTrue(warnings.contains { $0.kind == .security })
        let trees = document.blocks.compactMap { block -> TreeBlock? in if case let .tree(tree) = block { return tree }; return nil }
        XCTAssertTrue(trees.flatMap(\.roots).contains(where: containsUnsafeNode))
    }

    func testArchivePolicyBlocksInspection() async throws {
        let file = try temporaryFile(named: "blocked.zip", contents: makeZip(entries: [("a.txt", Data())]))
        defer { remove(file) }
        var policy = PreviewPolicy.default
        policy.allowArchiveInspection = false

        let result = await configuredRuntime().preview(fileURL: file, policy: policy)
        guard case let .failed(error) = result else {
            return XCTFail("Expected archive policy failure, got \(result)")
        }
        XCTAssertEqual(error.reason, .securityPolicyViolation)
    }

    func testCompressedTarBuildsArchiveTree() async throws {
        let tar = makeTar(entries: [("nested/hello.txt", Data("hello".utf8))])
        let file = try temporaryFile(named: "fixture.tar.gz", contents: gzip(tar))
        defer { remove(file) }

        let result = await configuredRuntime().preview(fileURL: file)
        guard case let .success(document) = result else {
            return XCTFail("Expected TAR.GZ preview, got \(result)")
        }

        XCTAssertEqual(document.subtitle, "TAR.GZ archive")
        let roots = document.blocks.compactMap { block -> TreeBlock? in if case let .tree(tree) = block { return tree }; return nil }.flatMap(\.roots)
        XCTAssertTrue(roots.contains { $0.label == "nested" })
    }

    func testBoundedFileAccessRejectsReadOverBudget() async throws {
        let file = try temporaryFile(named: "large.txt", contents: Data(repeating: 65, count: 32))
        defer { remove(file) }
        let budget = ResourceBudget(maxBytesRead: 8, maxMemoryBytes: 1_024, maxCPUTimeMs: 1_000, maxOutputNodes: 100, maxArchiveEntries: 100, maxTextLines: 100)

        do {
            _ = try await FileAccess.read(file, length: 9, budget: budget)
            XCTFail("Expected read budget failure")
        } catch let error as PreviewError {
            XCTAssertEqual(error.reason, .tooLarge)
        }
    }

    func testTimeoutCancelsSlowProvider() async throws {
        let registry = ProviderRegistry()
        try await registry.register(SlowProvider())
        let runtime = PreviewRuntime(registry: registry)
        let file = try temporaryFile(named: "slow.txt", contents: Data("content".utf8))
        defer { remove(file) }
        var policy = PreviewPolicy.default
        policy.budget.maxCPUTimeMs = 20

        let result = await runtime.preview(fileURL: file, policy: policy)
        guard case let .failed(error) = result else {
            return XCTFail("Expected timeout, got \(result)")
        }
        XCTAssertEqual(error.reason, .timeout)
    }

    func testPluginManifestValidationRejectsUnsupportedPermission() throws {
        let manifest = PluginManifest(
            id: "com.example.previewx.sample",
            name: "Sample",
            version: "1.0.0",
            minimumPreviewXVersion: "1.0.0",
            supportedTypes: ["public.text"],
            extensions: ["sample"],
            capabilities: [.raw],
            permissions: ["external.process"]
        )

        XCTAssertThrowsError(try PluginManifestValidator.validate(manifest)) { error in
            XCTAssertEqual((error as? PreviewError)?.reason, .securityPolicyViolation)
        }
    }

    func testDefaultPolicyKeepsRemoteAIDisabled() {
        XCTAssertFalse(PreviewPolicy.default.allowRemoteAI)
    }

    func testSecretDetectionIsAdvisoryAndCanBeDisabled() async throws {
        let content = "API_KEY=previewx-test-token-123456\n"
        let file = try temporaryFile(named: ".env", contents: Data(content.utf8))
        defer { remove(file) }

        let protectedResult = await configuredRuntime().preview(fileURL: file)
        guard case let .partial(document, warnings) = protectedResult else {
            return XCTFail("Expected advisory secret warning, got \(protectedResult)")
        }
        XCTAssertTrue(warnings.contains { $0.kind == .security })
        XCTAssertTrue(document.blocks.contains {
            if case let .code(block) = $0 { return block.content.contains("previewx-test-token") }
            return false
        })

        var policy = PreviewPolicy.default
        policy.redactSecrets = false
        let unprotectedResult = await configuredRuntime().preview(fileURL: file, policy: policy)
        guard case .success = unprotectedResult else {
            return XCTFail("Expected preview without advisory warning, got \(unprotectedResult)")
        }
    }

    func testDiagnosticsPersistWithoutFileContent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PreviewXDiagnostics-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("diagnostics.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = DiagnosticsStore(fileURL: file)
        await store.record(PreviewDiagnostic(
            requestID: UUID(),
            filename: "private.env",
            providerID: "com.previewx.text",
            phase: .rendering,
            durationMs: 12,
            bytesRead: 128,
            status: .success
        ))

        let restored = DiagnosticsStore(fileURL: file)
        let events = await restored.recentEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.filename, "private.env")
        let persisted = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(persisted.contains("/"))
    }

    private func configuredRuntime() async -> PreviewRuntime {
        let registry = ProviderRegistry()
        let runtime = PreviewRuntime(registry: registry)
        try? await BuiltInProviders.registerAll(into: registry)
        return runtime
    }

    private func temporaryFile(named name: String, contents: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PreviewXTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(name)
        try contents.write(to: file)
        return file
    }

    private func remove(_ file: URL) {
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    private func containsUnsafeNode(_ node: TreeNode) -> Bool {
        node.isUnsafe || node.children.contains(where: containsUnsafeNode)
    }

    private func node(named label: String, in root: TreeNode) -> TreeNode? {
        if root.label == label { return root }
        for child in root.children {
            if let result = node(named: label, in: child) { return result }
        }
        return nil
    }

    func testByteFormatHelperProducesStandardEnglishUnits() {
        // Values from Figure 1
        XCTAssertEqual(ByteFormatHelper.format(UInt64(56)), "56 B")
        XCTAssertEqual(ByteFormatHelper.format(UInt64(15)), "15 B")
        XCTAssertEqual(ByteFormatHelper.format(UInt64(24)), "24 B")
        XCTAssertEqual(ByteFormatHelper.format(UInt64(17)), "17 B")
        XCTAssertEqual(ByteFormatHelper.format(UInt64(0)), "0 B")

        // KB, MB, GB values
        XCTAssertEqual(ByteFormatHelper.format(UInt64(1_024)), "1 KB")
        XCTAssertEqual(ByteFormatHelper.format(UInt64(1_536)), "1.5 KB")
        XCTAssertEqual(ByteFormatHelper.format(UInt64(10 * 1_024)), "10 KB")
        XCTAssertEqual(ByteFormatHelper.format(UInt64(1_048_576)), "1 MB")
        XCTAssertEqual(ByteFormatHelper.format(UInt64(2 * 1_048_576)), "2 MB")
        XCTAssertEqual(ByteFormatHelper.format(UInt64(1_073_741_824)), "1 GB")

        // Signed Int64 helper
        XCTAssertEqual(ByteFormatHelper.format(Int64(-1)), "-")
        XCTAssertEqual(ByteFormatHelper.format(Int64(56)), "56 B")
    }

    func testLanguageSettingsPersistenceAndLocalization() throws {
        var settings = PreviewXSettings()
        XCTAssertEqual(settings.language, .system)

        // Switch to Simplified Chinese
        settings.language = .zhHans
        XCTAssertTrue(settings.language.isChinese)
        XCTAssertEqual(settings.language.tr(.settings), "设置")
        XCTAssertEqual(settings.language.tr(.about), "关于 PreviewX")
        XCTAssertEqual(settings.language.tr(.designedAndDevelopedBy), "设计与开发")

        // Switch to English
        settings.language = .en
        XCTAssertFalse(settings.language.isChinese)
        XCTAssertEqual(settings.language.tr(.settings), "Settings")
        XCTAssertEqual(settings.language.tr(.about), "About PreviewX")
        XCTAssertEqual(settings.language.tr(.designedAndDevelopedBy), "Designed & Developed by")

        // Encode and decode test
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(PreviewXSettings.self, from: data)
        XCTAssertEqual(decoded.language, .en)

        // Backward compatibility: JSON missing language defaults to .system
        let legacyJSON = "{\"schemaVersion\":1}"
        let legacyDecoded = try JSONDecoder().decode(PreviewXSettings.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(legacyDecoded.language, .system)
    }

    func testBuiltInDockerfilePreviews() async throws {
        let file = try temporaryFile(named: "Dockerfile", contents: Data("FROM scratch\n".utf8))
        defer { remove(file) }

        let result = await configuredRuntime().preview(fileURL: file)
        guard let document = result.document else {
            return XCTFail("Expected Dockerfile preview, got \(result)")
        }
        XCTAssertEqual(document.subtitle, "Dockerfile")
        XCTAssertEqual(document.metadata.first(where: { $0.key == "Provider" })?.value, "Source Code")
    }

    func testBuiltInPhpExtensionPreviewsAsPHP() async throws {
        let file = try temporaryFile(named: "index.php", contents: Data("<?php echo 'ok';\n".utf8))
        defer { remove(file) }

        let result = await configuredRuntime().preview(fileURL: file)
        guard case let .success(document) = result else {
            return XCTFail("Expected PHP preview, got \(result)")
        }
        XCTAssertEqual(document.subtitle, "PHP")
    }

    func testFormatCategoryExpandedExtensionsAndSearch() {
        let categories = FormatCategory.makeCategories(language: .simplifiedChinese)
        XCTAssertEqual(categories.count, 5)

        let codeCat = categories.first(where: { $0.id == "code" })
        XCTAssertNotNil(codeCat)
        guard let code = codeCat else { return }
        XCTAssertTrue(code.sampleExtensions.count >= 60, "Code category should contain 60+ extensions, got \(code.sampleExtensions.count)")
        XCTAssertTrue(code.sampleExtensions.contains("vue"))
        XCTAssertTrue(code.sampleExtensions.contains("svelte"))
        XCTAssertTrue(code.sampleExtensions.contains("dart"))
        XCTAssertTrue(code.sampleExtensions.contains("cs"))
        XCTAssertTrue(code.sampleExtensions.contains("rb"))
        XCTAssertTrue(code.sampleExtensions.contains("Dockerfile"))
        XCTAssertTrue(code.sampleExtensions.contains("Makefile"))
        XCTAssertTrue(code.sampleExtensions.contains("cmake"))
        XCTAssertTrue(code.matches("vue"))
        XCTAssertTrue(code.matches(".vue"))
        XCTAssertTrue(code.matches("dockerfile"))

        let structuredCat = categories.first(where: { $0.id == "structured" })
        XCTAssertNotNil(structuredCat)
        guard let structured = structuredCat else { return }
        XCTAssertTrue(structured.sampleExtensions.contains("jsonc"))
        XCTAssertTrue(structured.sampleExtensions.contains("geojson"))
        XCTAssertTrue(structured.sampleExtensions.contains("svg"))
        XCTAssertTrue(structured.sampleExtensions.contains("plist"))
        XCTAssertTrue(structured.matches("plist"))
        XCTAssertTrue(structured.matches(".svg"))

        let archiveCat = categories.first(where: { $0.id == "archive" })
        XCTAssertNotNil(archiveCat)
        guard let archive = archiveCat else { return }
        XCTAssertTrue(archive.sampleExtensions.contains("jar"))
        XCTAssertTrue(archive.sampleExtensions.contains("apk"))
        XCTAssertTrue(archive.sampleExtensions.contains("tar.gz"))
        XCTAssertTrue(archive.matches("apk"))
        XCTAssertTrue(archive.matches(".tar.gz"))

        let docsCat = categories.first(where: { $0.id == "documents" })
        XCTAssertNotNil(docsCat)
        guard let docs = docsCat else { return }
        XCTAssertTrue(docs.sampleExtensions.contains("text"))
        XCTAssertTrue(docs.sampleExtensions.contains(".gitignore"))
        XCTAssertTrue(docs.matches("gitignore"))

        let dbCat = categories.first(where: { $0.id == "database" })
        XCTAssertNotNil(dbCat)
        guard let db = dbCat else { return }
        XCTAssertTrue(db.sampleExtensions.contains("wasm"))
        XCTAssertTrue(db.sampleExtensions.contains("dylib"))
        XCTAssertTrue(db.matches("wasm"))
        XCTAssertTrue(db.matches(".dylib"))
    }
}

private struct SlowProvider: PreviewProvider {
    let descriptor = ProviderDescriptor(id: "com.previewx.tests.slow", name: "Slow", extensions: ["txt"], priority: 100)

    func canPreview(_ request: PreviewRequest) async -> ProviderMatch {
        .init(confidence: 1_000, specificity: 100, reason: "Test provider")
    }

    func makePreview(_ request: PreviewRequest) async throws -> PreviewDocument {
        try await Task.sleep(nanoseconds: 250_000_000)
        return PreviewDocument(title: request.identity.filename, blocks: [.text(.init(content: "done"))])
    }
}

private func makeZip(entries: [(String, Data)]) -> Data {
    var output = Data()
    var directory = Data()
    var offsets: [UInt32] = []

    for (name, contents) in entries {
        let nameData = Data(name.utf8)
        offsets.append(UInt32(output.count))
        output.appendLE(UInt32(0x0403_4B50))
        output.appendLE(UInt16(20))
        output.appendLE(UInt16(0))
        output.appendLE(UInt16(0))
        output.appendLE(UInt16(0))
        output.appendLE(UInt16(0))
        output.appendLE(UInt32(0))
        output.appendLE(UInt32(contents.count))
        output.appendLE(UInt32(contents.count))
        output.appendLE(UInt16(nameData.count))
        output.appendLE(UInt16(0))
        output.append(nameData)
        output.append(contents)
    }

    let directoryOffset = UInt32(output.count)
    for (index, entry) in entries.enumerated() {
        let nameData = Data(entry.0.utf8)
        directory.appendLE(UInt32(0x0201_4B50))
        directory.appendLE(UInt16(20))
        directory.appendLE(UInt16(20))
        directory.appendLE(UInt16(0))
        directory.appendLE(UInt16(0))
        directory.appendLE(UInt16(0))
        directory.appendLE(UInt16(0))
        directory.appendLE(UInt32(0))
        directory.appendLE(UInt32(entry.1.count))
        directory.appendLE(UInt32(entry.1.count))
        directory.appendLE(UInt16(nameData.count))
        directory.appendLE(UInt16(0))
        directory.appendLE(UInt16(0))
        directory.appendLE(UInt16(0))
        directory.appendLE(UInt16(0))
        directory.appendLE(UInt32(0))
        directory.appendLE(offsets[index])
        directory.append(nameData)
    }
    output.append(directory)
    output.appendLE(UInt32(0x0605_4B50))
    output.appendLE(UInt16(0))
    output.appendLE(UInt16(0))
    output.appendLE(UInt16(entries.count))
    output.appendLE(UInt16(entries.count))
    output.appendLE(UInt32(directory.count))
    output.appendLE(directoryOffset)
    output.appendLE(UInt16(0))
    return output
}

private func makeTar(entries: [(String, Data)]) -> Data {
    var output = Data()
    for (name, contents) in entries {
        var header = Data(repeating: 0, count: 512)
        let nameData = Data(name.utf8.prefix(100))
        header.replaceSubrange(0..<nameData.count, with: nameData)
        let size = Data(String(format: "%011o\0", contents.count).utf8)
        header.replaceSubrange(124..<(124 + size.count), with: size)
        header[156] = 48
        header.replaceSubrange(257..<263, with: Data("ustar\0".utf8))
        output.append(header)
        output.append(contents)
        let padding = (512 - contents.count % 512) % 512
        output.append(Data(repeating: 0, count: padding))
    }
    output.append(Data(repeating: 0, count: 1_024))
    return output
}

private func gzip(_ input: Data) -> Data {
    input.withUnsafeBytes { rawInput in
        var stream = z_stream()
        stream.next_in = UnsafeMutablePointer(mutating: rawInput.bindMemory(to: Bytef.self).baseAddress)
        stream.avail_in = uInt(input.count)
        precondition(deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            16 + MAX_WBITS,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        ) == Z_OK)
        defer { deflateEnd(&stream) }

        var output = Data()
        var status: Int32 = Z_OK
        repeat {
            let capacity = 64 * 1_024
            var chunk = [UInt8](repeating: 0, count: capacity)
            let count = chunk.withUnsafeMutableBytes { rawOutput -> Int in
                stream.next_out = rawOutput.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(capacity)
                status = zlib.deflate(&stream, Z_FINISH)
                return capacity - Int(stream.avail_out)
            }
            output.append(contentsOf: chunk.prefix(count))
        } while status != Z_STREAM_END
        return output
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
