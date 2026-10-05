import Darwin
import Foundation
import PreviewXCore
import PreviewXProviders

@main
struct PreviewXCLI {
    static func main() async {
        let code = await run(arguments: Array(CommandLine.arguments.dropFirst()))
        exit(Int32(code))
    }

    private static func run(arguments: [String]) async -> Int {
        guard let command = arguments.first else {
            print(usage)
            return 2
        }

        switch command {
        case "preview":
            return await preview(arguments: Array(arguments.dropFirst()))
        case "providers":
            return await providers(arguments: Array(arguments.dropFirst()))
        case "diagnostics":
            return await diagnostics(arguments: Array(arguments.dropFirst()))
        case "validate-plugin":
            return validatePlugin(arguments: Array(arguments.dropFirst()))
        case "benchmark":
            return await benchmark(arguments: Array(arguments.dropFirst()))
        case "help", "--help", "-h":
            print(usage)
            return 0
        default:
            writeError("Unknown command: \(command)")
            print(usage)
            return 2
        }
    }

    private static func preview(arguments: [String]) async -> Int {
        guard let path = arguments.first, !path.hasPrefix("-") else {
            writeError("preview requires a file path.")
            return 2
        }
        let format = value(after: "--format", in: arguments) ?? "text"
        guard ["text", "json"].contains(format) else {
            writeError("--format must be text or json.")
            return 2
        }
        let runtime = await BuiltInProviders.makeRuntime()
        let providerID = value(after: "--provider", in: arguments)
        var policy = PreviewPolicy.default
        policy.preferredProviderID = providerID
        let result = await runtime.preview(fileURL: URL(fileURLWithPath: path), policy: policy)
        if format == "json" {
            printJSON(CLIResult(result: result))
        } else {
            printHuman(result: result)
        }
        return exitCode(for: result)
    }

    private static func providers(arguments: [String]) async -> Int {
        guard let subcommand = arguments.first else {
            writeError("providers requires list or doctor.")
            return 2
        }
        let runtime = await BuiltInProviders.makeRuntime()
        let descriptors = await runtime.registry.descriptors()
        switch subcommand {
        case "list":
            if value(after: "--format", in: arguments) == "json" {
                printJSON(descriptors)
            } else {
                for descriptor in descriptors {
                    let extensions = descriptor.extensions.isEmpty ? "type-only" : descriptor.extensions.joined(separator: ", ")
                    print("\(descriptor.id)\n  \(descriptor.name) \(descriptor.version) | \(extensions)")
                }
            }
            return 0
        case "doctor":
            let duplicateIDs = Dictionary(grouping: descriptors, by: \.id).filter { $0.value.count > 1 }.keys
            if duplicateIDs.isEmpty && !descriptors.isEmpty {
                print("Provider registry is healthy (\(descriptors.count) built-in providers registered).")
                return 0
            }
            writeError("Provider registry health check failed.")
            return 1
        default:
            writeError("Unknown providers subcommand: \(subcommand)")
            return 2
        }
    }

    private static func diagnostics(arguments: [String]) async -> Int {
        guard arguments.first == "export" else {
            writeError("diagnostics requires export.")
            return 2
        }
        let runtime = await BuiltInProviders.makeRuntime()
        let descriptors = await runtime.registry.descriptors()
        let snapshot = DiagnosticExport(
            generatedAt: Date(),
            appVersion: "1.0.0",
            providers: descriptors,
            events: await runtime.diagnostics.recentEvents()
        )
        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            data = try encoder.encode(snapshot)
        } catch {
            writeError("Unable to encode diagnostics: \(error.localizedDescription)")
            return 1
        }
        if let destination = arguments.dropFirst().first, !destination.hasPrefix("-") {
            do {
                try data.write(to: URL(fileURLWithPath: destination), options: .atomic)
                print("Diagnostics exported to \(destination)")
            } catch {
                writeError("Unable to write diagnostics: \(error.localizedDescription)")
                return 1
            }
        } else {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
        return 0
    }

    private static func validatePlugin(arguments: [String]) -> Int {
        guard let path = arguments.first else {
            writeError("validate-plugin requires manifest.json or a .pxplugin directory.")
            return 2
        }
        let inputURL = URL(fileURLWithPath: path)
        let manifestURL: URL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            manifestURL = inputURL.appendingPathComponent("manifest.json")
        } else {
            manifestURL = inputURL
        }
        do {
            let manifest = try JSONDecoder().decode(PluginManifest.self, from: Data(contentsOf: manifestURL))
            try PluginManifestValidator.validate(manifest)
            print("Plugin manifest is valid: \(manifest.id) \(manifest.version)")
            return 0
        } catch let error as PreviewError {
            writeError(error.message)
            return error.reason == .securityPolicyViolation ? 5 : 3
        } catch {
            writeError("Invalid plugin manifest: \(error.localizedDescription)")
            return 3
        }
    }

    private static func benchmark(arguments: [String]) async -> Int {
        guard let path = arguments.first, !path.hasPrefix("-") else {
            writeError("benchmark requires a file path.")
            return 2
        }
        let iterations = Int(value(after: "--iterations", in: arguments) ?? "3") ?? 3
        guard (1...20).contains(iterations) else {
            writeError("--iterations must be between 1 and 20.")
            return 2
        }
        let runtime = await BuiltInProviders.makeRuntime()
        var durations: [Double] = []
        var finalResult: PreviewResult = .unsupported("No run completed")
        for _ in 0..<iterations {
            let start = ContinuousClock.now
            finalResult = await runtime.preview(fileURL: URL(fileURLWithPath: path))
            let duration = start.duration(to: .now).components
            durations.append(Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
        }
        let sorted = durations.sorted()
        let median = sorted[sorted.count / 2]
        print("Iterations: \(iterations)")
        print("Median: \(String(format: "%.2f", median)) ms")
        print("Best: \(String(format: "%.2f", sorted.first ?? 0)) ms")
        print("Worst: \(String(format: "%.2f", sorted.last ?? 0)) ms")
        return exitCode(for: finalResult)
    }

    private static func printHuman(result: PreviewResult) {
        switch result {
        case let .success(document), let .partial(document, _):
            print("\(document.title)\(document.subtitle.map { " - \($0)" } ?? "")")
            for item in document.metadata {
                print("\(item.key): \(item.value)")
            }
            for warning in document.warnings {
                print("Warning: \(warning.message)")
            }
            for block in document.presentationBlocks {
                switch block {
                case let .text(block):
                    print("\n\(block.content)")
                case let .code(block):
                    print("\n\(block.content)")
                case let .tree(block):
                    print("\n\(block.title)")
                    for root in block.roots { printTree(root) }
                case let .table(block):
                    print("\n\(block.title)")
                    print(block.columns.joined(separator: " | "))
                    for row in block.rows.prefix(50) { print(row.joined(separator: " | ")) }
                case let .error(block):
                    writeError("\(block.title): \(block.message)")
                case let .markdown(block):
                    for node in block.nodes {
                        switch node.kind {
                        case .heading:
                            print("\n\(String(repeating: "#", count: max(1, node.level))) \(node.text)")
                        case .listItem:
                            print("\(String(repeating: "  ", count: node.level))- \(node.text)")
                        case .orderedListItem:
                            print("\(String(repeating: "  ", count: node.level))1. \(node.text)")
                        case .taskItem:
                            let marker = node.isDone == true ? "[x]" : "[ ]"
                            print("\(String(repeating: "  ", count: node.level))\(marker) \(node.text)")
                        case .quote:
                            print("> \(node.text)")
                        case .codeBlock:
                            print("\n```\(node.language ?? "")")
                            print(node.text)
                            print("```")
                        case .thematicBreak:
                            print("\n---")
                        case .paragraph:
                            print("\n\(node.text)")
                        case .table:
                            print("\n\(node.text)")
                        }
                    }
                }
            }
        case let .unsupported(message):
            writeError("Unsupported: \(message)")
        case let .failed(error):
            writeError("\(error.reason.rawValue): \(error.message)")
        }
    }

    private static func printTree(_ node: TreeNode, depth: Int = 0) {
        let marker = node.isUnsafe ? " [unsafe]" : ""
        print("\(String(repeating: "  ", count: depth))- \(node.label)\(node.value.map { ": \($0)" } ?? "")\(marker)")
        for child in node.children { printTree(child, depth: depth + 1) }
    }

    private static func printJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(value) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    private static func exitCode(for result: PreviewResult) -> Int {
        switch result {
        case .success, .partial: return 0
        case .unsupported: return 4
        case let .failed(error):
            return error.reason == .securityPolicyViolation ? 5 : 1
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data("previewx: \(message)\n".utf8))
    }

    private static let usage = """
    Usage:
      previewx preview <file> [--format text|json] [--provider provider-id]
      previewx providers list [--format text|json]
      previewx providers doctor
      previewx diagnostics export [output.json]
      previewx validate-plugin <manifest.json|plugin-directory>
      previewx benchmark <file> [--iterations 3]
    """
}

private struct CLIResult: Codable {
    let status: String
    let document: PreviewDocument?
    let message: String?

    init(result: PreviewResult) {
        switch result {
        case let .success(document):
            status = "success"
            self.document = document
            message = nil
        case let .partial(document, warnings):
            status = "partial"
            self.document = document
            message = warnings.map(\.message).joined(separator: " ")
        case let .unsupported(reason):
            status = "unsupported"
            document = nil
            message = reason
        case let .failed(error):
            status = "failed"
            document = nil
            message = error.message
        }
    }
}

private struct DiagnosticExport: Codable {
    let generatedAt: Date
    let appVersion: String
    let providers: [ProviderDescriptor]
    let events: [PreviewDiagnostic]
}
