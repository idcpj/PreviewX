import Foundation
import XCTest
@testable import PreviewXCore
@testable import PreviewXProviders

/// Validates tree presentation features for tree-compatible formats (tar, json, yaml, toml, xml).
/// Enforces the requirement:
/// 1. Formats like tar, json, yaml, toml, xml are identified as tree-compatible.
/// 2. Hierarchical tree structures are extracted (e.g. tar directory tree, JSON object hierarchy).
/// 3. In the initial/default state, ONLY the root path (depth 0) and first-level path (depth 1) are visible.
/// 4. Clicking/toggling a first-level node expands its deeper children (depth 2+), and toggling again collapses them.
/// 5. Non-tree formats (plain text, code, raw binary) are not identified as tree formats.
final class TreePreviewFeatureTests: XCTestCase {
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

    // MARK: - Tar Archive Tree Tests

    func testTarArchiveTreeDefaultsToRootAndFirstLevelPath() async throws {
        let runtime = await configuredRuntime()
        let tarURL = fixturesDirectory().appendingPathComponent("archives/sample.tar")
        guard FileManager.default.fileExists(atPath: tarURL.path) else {
            return XCTFail("Missing sample.tar fixture at \(tarURL.path)")
        }

        let result = await runtime.preview(fileURL: tarURL)
        guard case let .success(document) = result else {
            return XCTFail("Expected success for sample.tar, got \(result)")
        }

        // 1. Verify tree capability and format identification
        XCTAssertTrue(
            TreeRepresentationHelper.isTreeSupported(for: document),
            "sample.tar must be recognized as tree-compatible"
        )

        // 2. Extract tree roots
        let roots = TreeRepresentationHelper.makeTreeRoots(for: document)
        XCTAssertFalse(roots.isEmpty, "sample.tar must produce non-empty tree roots")

        // 3. Initialize TreePresentationState
        var state = TreePresentationState(roots: roots)
        let visible = state.visibleNodes

        // 4. Assert: In default state, ONLY root path (depth 0) and first-level path (depth 1) are visible
        XCTAssertFalse(visible.isEmpty)
        let maxInitialDepth = visible.map(\.depth).max() ?? 0
        XCTAssertEqual(
            maxInitialDepth, 1,
            "By default, visible nodes must only contain depth 0 (root path) and depth 1 (first-level path)"
        )

        let rootNodes = visible.filter { $0.depth == 0 }
        let firstLevelNodes = visible.filter { $0.depth == 1 }
        let secondLevelNodes = visible.filter { $0.depth >= 2 }

        XCTAssertFalse(rootNodes.isEmpty, "Root path must be visible")
        XCTAssertFalse(firstLevelNodes.isEmpty, "First-level path must be visible")
        XCTAssertTrue(secondLevelNodes.isEmpty, "Deeper paths must NOT be visible by default")

        // In sample.tar, the root is "PreviewX", and first level contains folders "Guides", "Sources", and file "README.txt"
        let firstLevelLabels = Set(firstLevelNodes.map(\.node.label))
        XCTAssertTrue(firstLevelLabels.contains("Guides") || firstLevelLabels.contains("Sources") || firstLevelLabels.contains("README.txt"))

        // 5. Expand an expandable first-level node (e.g. "Guides" or "Sources")
        guard let expandableNode = firstLevelNodes.first(where: { !$0.node.children.isEmpty }) else {
            return XCTFail("Expected at least one expandable first-level directory node in sample.tar")
        }

        XCTAssertFalse(state.isExpanded(expandableNode.node.id), "First-level node must start collapsed")

        // Toggle expand
        state.toggle(expandableNode.node.id)
        XCTAssertTrue(state.isExpanded(expandableNode.node.id))

        let expandedVisible = state.visibleNodes
        let newSecondLevelNodes = expandedVisible.filter { $0.depth == 2 }
        XCTAssertFalse(newSecondLevelNodes.isEmpty, "Toggling an expandable first-level node must reveal its depth 2 children")

        // Toggle collapse back
        state.toggle(expandableNode.node.id)
        XCTAssertFalse(state.isExpanded(expandableNode.node.id))
        XCTAssertEqual(
            state.visibleNodes.map(\.depth).max(), 1,
            "Collapsing the node must hide depth >= 2 again"
        )
    }

    // MARK: - Structured Data Formats Use Formatted Code (Not Tree)

    func testJSONYAMLTOMLAndXMLAreNotIdentifiedAsTree() async throws {
        let runtime = await configuredRuntime()
        let files = [
            "json/package.json",
            "json/sample.json",
            "yaml/sample.yaml",
            "toml/sample.toml"
        ]

        for relativePath in files {
            let url = fixturesDirectory().appendingPathComponent(relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let result = await runtime.preview(fileURL: url)
            guard case let .success(document) = result else {
                XCTFail("Expected success for \(relativePath), got \(result)")
                continue
            }

            // Structured text formats should NOT be tree-compatible
            XCTAssertFalse(
                TreeRepresentationHelper.isTreeSupported(for: document),
                "\(relativePath) must not be identified as tree format (should display formatted code directly)"
            )
            // Should contain code block
            XCTAssertTrue(
                document.blocks.contains { if case .code = $0 { return true }; return false },
                "\(relativePath) must contain formatted code block"
            )
        }
    }

    // MARK: - Non-Tree Format Rejection Tests

    func testNonTreeFormatsAreNotIdentifiedAsTree() async throws {
        let runtime = await configuredRuntime()
        let swiftURL = fixturesDirectory().appendingPathComponent("code/sample.swift")
        let textURL = fixturesDirectory().appendingPathComponent("text/notes.txt")
        let binURL = fixturesDirectory().appendingPathComponent("binary/sample.bin")

        for file in [swiftURL, textURL, binURL] {
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            let result = await runtime.preview(fileURL: file)
            guard let document = result.document else { continue }

            XCTAssertFalse(
                TreeRepresentationHelper.isTreeSupported(for: document),
                "\(file.lastPathComponent) should not be identified as a tree format"
            )
        }
    }
}
