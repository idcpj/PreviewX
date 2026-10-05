import Foundation

/// Represents a node within a flattened tree presentation, pairing the underlying `TreeNode`
/// with its hierarchical depth for indented indentation and deterministic testing.
public struct VisibleTreeNode: Identifiable, Equatable, Sendable {
    public let node: TreeNode
    public let depth: Int

    public var id: UUID { node.id }

    public init(node: TreeNode, depth: Int) {
        self.node = node
        self.depth = depth
    }
}

/// State machine managing tree expansion and visible row calculation.
/// Enforces the requirement that by default only the root path (depth 0) and
/// first-level path (depth 1) are displayed.
public struct TreePresentationState: Equatable, Sendable {
    public let roots: [TreeNode]
    public var expandedNodeIDs: Set<UUID>

    /// Initializes state with root nodes.
    /// By default, only depth 0 nodes (the roots) are expanded, which makes depth 1 (first-level path)
    /// visible, while deeper descendants (depth >= 2) remain collapsed.
    public init(roots: [TreeNode]) {
        self.roots = roots
        self.expandedNodeIDs = Set(roots.map(\.id))
    }

    /// Computes the flattened list of visible nodes according to the current expansion state.
    public var visibleNodes: [VisibleTreeNode] {
        var result: [VisibleTreeNode] = []
        func traverse(nodes: [TreeNode], depth: Int) {
            for node in nodes {
                result.append(VisibleTreeNode(node: node, depth: depth))
                if expandedNodeIDs.contains(node.id) && !node.children.isEmpty {
                    traverse(nodes: node.children, depth: depth + 1)
                }
            }
        }
        traverse(nodes: roots, depth: 0)
        return result
    }

    /// Toggles the expansion state of a specific node.
    public mutating func toggle(_ nodeID: UUID) {
        if expandedNodeIDs.contains(nodeID) {
            expandedNodeIDs.remove(nodeID)
        } else {
            expandedNodeIDs.insert(nodeID)
        }
    }

    /// Checks if a node is currently expanded.
    public func isExpanded(_ nodeID: UUID) -> Bool {
        expandedNodeIDs.contains(nodeID)
    }

    /// Collapses the tree back to its default state: only root nodes expanded,
    /// so only root and first-level paths are visible.
    public mutating func collapseToDefault() {
        expandedNodeIDs = Set(roots.map(\.id))
    }

    /// Expands all nodes that have children.
    public mutating func expandAll() {
        var all: Set<UUID> = []
        func collect(nodes: [TreeNode]) {
            for node in nodes {
                if !node.children.isEmpty {
                    all.insert(node.id)
                    collect(nodes: node.children)
                }
            }
        }
        collect(nodes: roots)
        expandedNodeIDs = all
    }
}

/// Parser that converts JSON structured data into a hierarchical `TreeNode` list.
public enum JSONTreeBuilder {
    /// Builds tree nodes from raw JSON text, optionally wrapping them in a root title node.
    public static func build(from jsonString: String, rootTitle: String? = nil) -> [TreeNode]? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        let children = nodeChildren(from: jsonObject)
        if let rootTitle = rootTitle, !rootTitle.isEmpty {
            return [TreeNode(label: rootTitle, value: summary(of: jsonObject), children: children)]
        }
        return children
    }

    private static func summary(of object: Any) -> String? {
        if let dict = object as? [String: Any] {
            let count = dict.count
            return "{\(count) \(count == 1 ? "key" : "keys")}"
        } else if let arr = object as? [Any] {
            let count = arr.count
            return "[\(count) \(count == 1 ? "item" : "items")]"
        }
        return nil
    }

    private static func nodeChildren(from object: Any) -> [TreeNode] {
        if let dict = object as? [String: Any] {
            return dict.keys.sorted().map { key in
                let val = dict[key]!
                return makeNode(label: key, value: val)
            }
        } else if let arr = object as? [Any] {
            return arr.enumerated().map { index, val in
                makeNode(label: "[\(index)]", value: val)
            }
        }
        return []
    }

    private static func makeNode(label: String, value: Any) -> TreeNode {
        if let dict = value as? [String: Any] {
            let count = dict.count
            let desc = "{\(count) \(count == 1 ? "key" : "keys")}"
            return TreeNode(label: label, value: desc, children: nodeChildren(from: dict))
        } else if let arr = value as? [Any] {
            let count = arr.count
            let desc = "[\(count) \(count == 1 ? "item" : "items")]"
            return TreeNode(label: label, value: desc, children: nodeChildren(from: arr))
        } else if let str = value as? String {
            return TreeNode(label: label, value: "\"\(str)\"")
        } else if let num = value as? NSNumber {
            if CFBooleanGetTypeID() == CFGetTypeID(num) {
                return TreeNode(label: label, value: num.boolValue ? "true" : "false")
            }
            return TreeNode(label: label, value: "\(num)")
        } else if value is NSNull {
            return TreeNode(label: label, value: "null")
        } else {
            return TreeNode(label: label, value: String(describing: value))
        }
    }
}

/// Helper that identifies tree-compatible formats and extracts their hierarchical nodes.
public enum TreeRepresentationHelper {
    /// Determines whether a preview document can be displayed in a tree structure.
    /// Supports archive formats (tar, zip, tgz), JSON, YAML, TOML, XML, etc.
    public static func isTreeSupported(for document: PreviewDocument) -> Bool {
        // Only actual tree blocks with non-empty roots (such as archive files)
        if document.blocks.contains(where: {
            if case let .tree(tree) = $0, !tree.roots.isEmpty { return true }
            return false
        }) {
            return true
        }
        return false
    }

    /// Extracts or constructs hierarchical tree roots from the preview document.
    public static func makeTreeRoots(for document: PreviewDocument) -> [TreeNode] {
        // 1. Existing tree blocks directly provide their hierarchy
        for block in document.blocks {
            if case let .tree(tree) = block, !tree.roots.isEmpty {
                return tree.roots
            }
        }

        // 2. JSON document parsing (wraps with document title as root)
        if let jsonBlock = document.blocks.compactMap({ block -> CodeBlock? in
            if case let .code(code) = block, code.language.lowercased() == "json" { return code }
            return nil
        }).first {
            if let roots = JSONTreeBuilder.build(from: jsonBlock.content, rootTitle: document.title), !roots.isEmpty {
                return roots
            }
        }

        return []
    }

    /// Normalizes tree roots. If roots already represent a single directory node with children
    /// (typical for tar archives like `PreviewX/`), keep it intact. Otherwise wrap them with
    /// the document title as the single root path node so that the root path is always depth 0.
    public static func normalizeRoots(_ roots: [TreeNode], documentTitle: String) -> [TreeNode] {
        if roots.count == 1 && !roots[0].children.isEmpty {
            return roots
        }
        return [TreeNode(label: documentTitle, children: roots)]
    }
}
