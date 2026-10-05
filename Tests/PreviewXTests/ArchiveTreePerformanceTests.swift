import XCTest
import UniformTypeIdentifiers
import AppKit
@testable import PreviewXCore
@testable import PreviewXProviders
@testable import PreviewXUI

final class ArchiveTreePerformanceTests: XCTestCase {

    @MainActor
    func testNativeFileIconProviderPrewarmAndLookupPerformance() {
        // 1. 验证预热能力
        let prewarmStart = CFAbsoluteTimeGetCurrent()
        NativeFileIconProvider.prewarm()
        let prewarmDuration = CFAbsoluteTimeGetCurrent() - prewarmStart
        print("[Performance Benchmark] NativeFileIconProvider.prewarm() took: \(String(format: "%.4f", prewarmDuration * 1000)) ms")
        
        // 2. 文件夹图标查找必须是 0 延迟单例引用（耗时 < 0.001 ms）
        let folderStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<10_000 {
            _ = NativeFileIconProvider.icon(for: "some_folder", isDirectory: true)
        }
        let folderDuration = CFAbsoluteTimeGetCurrent() - folderStart
        let avgFolderUs = (folderDuration / 10_000.0) * 1_000_000.0
        print("[Performance Benchmark] 10,000 folder icon lookups took: \(String(format: "%.4f", folderDuration * 1000)) ms, avg: \(String(format: "%.3f", avgFolderUs)) µs per lookup")
        XCTAssertLessThan(folderDuration, 0.05, "Folder icon lookups must be near-instantaneous (< 5 µs per lookup)")

        // 3. 预热后常见文件图标查找（swift, json, txt, zip 等）
        let files = [
            "main.swift", "package.json", "README.md", "app.log", "data.csv",
            "archive.tar.gz", "photo.png", "document.pdf", "schema.sql", "config.toml"
        ]
        let fileStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<1_000 {
            for file in files {
                _ = NativeFileIconProvider.icon(for: file, isDirectory: false)
            }
        }
        let fileDuration = CFAbsoluteTimeGetCurrent() - fileStart
        let avgFileUs = (fileDuration / 10_000.0) * 1_000_000.0
        print("[Performance Benchmark] 10,000 cached file icon lookups took: \(String(format: "%.4f", fileDuration * 1000)) ms, avg: \(String(format: "%.3f", avgFileUs)) µs per lookup")
        XCTAssertLessThan(fileDuration, 0.08, "Cached icon lookups must be under 8 µs per lookup to guarantee 120fps UI render")
    }

    @MainActor
    func testUncachedColdFileIconsNeverBlockMainThread() {
        // 测试当遇到 100 个从未见过的完全陌生后缀时，主线程是否会被 LaunchServices IPC 同步卡死
        let coldStart = CFAbsoluteTimeGetCurrent()
        for i in 0..<100 {
            let fakeFile = "unseen_document_\(i).unknown_ext_\(i)"
            let icon = NativeFileIconProvider.icon(for: fakeFile, isDirectory: false)
            XCTAssertNotNil(icon)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - coldStart
        let avgPerColdLookupMs = (elapsed / 100.0) * 1000.0
        print("[Performance Benchmark] 100 uncached cold icon lookups took: \(String(format: "%.4f", elapsed * 1000)) ms, avg: \(String(format: "%.4f", avgPerColdLookupMs)) ms per lookup")
        // 如果是同步调用 IPC，100 次耗时可高达 500ms ~ 1000ms；在异步解耦后，100 次必须在 5ms 以内瞬间完成！
        XCTAssertLessThan(elapsed, 0.005, "Uncached icons must return instantly (< 5ms for 100 items) via non-blocking default fallback")
    }

    func testTreeStateTogglePerformance() {
        // 构建包含 500 个节点的深层大纲树（50个目录，每个目录下 10 个文件）
        var allNodes: [TreeNode] = []
        for d in 0..<50 {
            var files: [TreeNode] = []
            for f in 0..<10 {
                files.append(TreeNode(
                    label: "file_\(d)_\(f).swift",
                    value: "10 KB",
                    detailColumns: ["2026-03-30 12:00", "10 KB", "3 KB"]
                ))
            }
            allNodes.append(TreeNode(
                label: "dir_\(d)",
                value: "10 items",
                detailColumns: ["2026-03-30 12:00", "100 KB", "30 KB"],
                children: files
            ))
        }
        let root = TreeNode(label: "root", children: allNodes)
        var state = TreePresentationState(roots: [root])

        // 测量 100 次切换展开/折叠状态并重新派生可见节点的总耗时
        let startTime = CFAbsoluteTimeGetCurrent()
        for i in 0..<100 {
            let targetNode = allNodes[i % allNodes.count]
            state.toggle(targetNode.id)
            let visible = state.visibleNodes
            XCTAssertGreaterThan(visible.count, 0)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let avgPerToggleMs = (elapsed / 100.0) * 1000.0

        print("[Performance Benchmark] 100 tree toggles on 500-node tree took: \(String(format: "%.4f", elapsed * 1000)) ms, avg: \(String(format: "%.3f", avgPerToggleMs)) ms per toggle")
        // 每次状态派生必须在 1ms 以内，确保与原生 Finder 体验一致
        XCTAssertLessThan(avgPerToggleMs, 1.0, "Tree toggle calculation must be instantaneous (< 1ms per toggle)")
    }

    func testLargeTreeScalabilityPerformance() {
        // 压力测试：构建包含 2,000 个节点的大型目录结构
        var allDirs: [TreeNode] = []
        for d in 0..<100 {
            var items: [TreeNode] = []
            for f in 0..<20 {
                items.append(TreeNode(
                    label: "item_\(d)_\(f).rs",
                    value: "4 KB",
                    detailColumns: ["2026-10-04 10:00", "4 KB", "1.2 KB"]
                ))
            }
            allDirs.append(TreeNode(
                label: "subpackage_\(d)",
                value: "20 items",
                detailColumns: ["2026-10-04 10:00", "80 KB", "24 KB"],
                children: items
            ))
        }
        let root = TreeNode(label: "workspace", children: allDirs)
        var state = TreePresentationState(roots: [root])

        let start = CFAbsoluteTimeGetCurrent()
        // 连续展开 10 个子目录
        for i in 0..<10 {
            state.toggle(allDirs[i].id)
        }
        let visibleCount = state.visibleNodes.count
        let duration = CFAbsoluteTimeGetCurrent() - start

        print("[Performance Benchmark] Expanding 10 directories in 2,000-node tree yielded \(visibleCount) visible nodes in \(String(format: "%.4f", duration * 1000)) ms")
        XCTAssertGreaterThan(visibleCount, 200)
        XCTAssertLessThan(duration, 0.05, "Even on 2,000 nodes, 10 continuous expansions must complete within 50ms")
    }

    /// 模拟 ArchiveTreeView 中 toggle + rebuildVisibleRows 的完整流程。
    /// 之前的测试仅覆盖 TreePresentationState（纯数据层），
    /// 未覆盖 UI 层 rebuildVisibleRows 的数组重建开销。
    /// 此测试确保即使在 5,000 节点的大树中，每次 toggle 后重建可见行
    /// 数组的耗时也不超过 0.5ms（对应 120fps 的帧预算 8.3ms 的 6%）。
    func testRebuildVisibleRowsPerformanceAtScale() {
        // 构建 5,000 节点的大树：100 个目录 × 50 个文件
        var allDirs: [TreeNode] = []
        for d in 0..<100 {
            var files: [TreeNode] = []
            for f in 0..<50 {
                files.append(TreeNode(
                    label: "file_\(d)_\(f).swift",
                    value: "\(f + 1) KB",
                    detailColumns: ["2026-10-04 12:00", "\(f + 1) KB", "\(f) KB"]
                ))
            }
            allDirs.append(TreeNode(
                label: "module_\(d)",
                value: "50 items",
                detailColumns: ["2026-10-04 12:00", "500 KB", "200 KB"],
                children: files
            ))
        }
        let root = TreeNode(label: "archive_root", children: allDirs)

        // 模拟 ArchiveTreeView 的 rebuildVisibleRows 流程
        var expandedIDs = Set<UUID>([root.id])
        let roots = [root]

        func rebuildVisibleRows() -> Int {
            var result: [(TreeNode, Int)] = []
            result.reserveCapacity(roots.count * 4)
            func collect(nodes: [TreeNode], depth: Int) {
                for node in nodes {
                    result.append((node, depth))
                    if expandedIDs.contains(node.id) && !node.children.isEmpty {
                        collect(nodes: node.children, depth: depth + 1)
                    }
                }
            }
            collect(nodes: roots, depth: 0)
            return result.count
        }

        // 展开前 20 个目录
        for i in 0..<20 {
            expandedIDs.insert(allDirs[i].id)
        }

        // 测量 50 次连续 toggle + rebuild 的总耗时
        let start = CFAbsoluteTimeGetCurrent()
        for i in 0..<50 {
            let target = allDirs[i % allDirs.count]
            if expandedIDs.contains(target.id) {
                expandedIDs.remove(target.id)
            } else {
                expandedIDs.insert(target.id)
            }
            let count = rebuildVisibleRows()
            XCTAssertGreaterThan(count, 0)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let avgPerToggleMs = (elapsed / 50.0) * 1000.0

        print("[Performance Benchmark] 50 toggle+rebuild cycles on 5,000-node tree took: \(String(format: "%.4f", elapsed * 1000)) ms, avg: \(String(format: "%.4f", avgPerToggleMs)) ms per cycle")
        // 每次 toggle + rebuild 必须在 0.5ms 以内，确保不阻塞 UI 主线程
        XCTAssertLessThan(avgPerToggleMs, 0.5, "rebuildVisibleRows must complete under 0.5ms per toggle to guarantee smooth UI at 120fps")
    }

    /// 端到端测试：使用真实的 sample.tar fixture 验证从解析到树构建到展开全链路的性能。
    func testRealSampleTarEndToEndPerformance() async throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // PreviewXTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures/archives/sample.tar")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            XCTFail("sample.tar fixture not found at \(fixtureURL.path)")
            return
        }

        let runtime = await BuiltInProviders.makeRuntime()
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = await runtime.preview(fileURL: fixtureURL)
        let previewDuration = CFAbsoluteTimeGetCurrent() - startTime

        // 验证解析成功
        switch result {
        case .success(let doc), .partial(let doc, _):
            // 验证产出了树块
            let hasTree = doc.blocks.contains { block in
                if case let .tree(tree) = block, !tree.roots.isEmpty { return true }
                return false
            }
            XCTAssertTrue(hasTree, "sample.tar must produce a tree block")

            // 提取树的根节点并构建 TreePresentationState
            if let treeBlock = doc.blocks.compactMap({ block -> TreeBlock? in
                if case let .tree(tree) = block { return tree }
                return nil
            }).first {
                var state = TreePresentationState(roots: treeBlock.roots)

                // 测量展开所有节点
                let expandStart = CFAbsoluteTimeGetCurrent()
                state.expandAll()
                let allVisible = state.visibleNodes
                let expandDuration = CFAbsoluteTimeGetCurrent() - expandStart

                print("[Performance Benchmark] sample.tar end-to-end: preview=\(String(format: "%.4f", previewDuration * 1000))ms, expandAll=\(String(format: "%.4f", expandDuration * 1000))ms, visible nodes=\(allVisible.count)")

                // 解析+树构建必须在 50ms 以内
                XCTAssertLessThan(previewDuration, 0.05, "sample.tar preview must complete within 50ms")
                // expandAll 必须在 1ms 以内
                XCTAssertLessThan(expandDuration, 0.001, "expandAll on sample.tar tree must complete within 1ms")
                XCTAssertGreaterThan(allVisible.count, 3, "sample.tar must have at least 4 visible nodes when fully expanded")
            }
        case .unsupported(let reason):
            XCTFail("sample.tar was unsupported: \(reason)")
        case .failed(let error):
            XCTFail("sample.tar preview failed: \(error.message)")
        }
    }
}
