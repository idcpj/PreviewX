import Foundation
import UniformTypeIdentifiers
import PreviewXCore
import PreviewXProviders

@main
struct AuditFixtures {
    static func main() async {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tests/Fixtures")
        
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            print("Cannot read fixtures dir")
            return
        }
        
        let registry = ProviderRegistry()
        let runtime = PreviewRuntime(registry: registry)
        try? await BuiltInProviders.registerAll(into: registry)
        
        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true && url.lastPathComponent != "README.md" {
                files.append(url)
            }
        }
        files.sort { $0.path < $1.path }
        
        print("Total fixture files: \(files.count)")
        print("--------------------------------------------------")
        
        for file in files {
            let relPath = file.path.replacingOccurrences(of: root.path + "/", with: "")
            let ext = file.pathExtension.lowercased()
            let uti = UTType(filenameExtension: ext)?.identifier ?? "nil"
            let identity = FileIdentity(url: file, filename: file.lastPathComponent, size: (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(UInt64.init)) ?? 0)
            let classification = await FileClassifier().classify(identity: identity, budget: .default)
            
            let result = await runtime.preview(fileURL: file)
            switch result {
            case .success(let doc):
                let blockTypes = doc.blocks.map { block -> String in
                    switch block {
                    case .code: return "code"
                    case .text: return "text"
                    case .tree: return "tree"
                    case .table: return "table"
                    case .markdown: return "markdown"
                    case .error: return "error"
                    }
                }.joined(separator: ",")
                print("SUCCESS | \(relPath) | ext:\(ext) | UTI:\(uti) | Subtitle:\(doc.subtitle ?? "none") | Blocks:[\(blockTypes)] | Provider:\(doc.metadata.first(where: { $0.key == "Provider" })?.value ?? "none")")
            case .partial(let doc, let warnings):
                let warns = warnings.map { "\($0.kind)" }.joined(separator: ",")
                let blockTypes = doc.blocks.map { block -> String in
                    switch block {
                    case .code: return "code"
                    case .text: return "text"
                    case .tree: return "tree"
                    case .table: return "table"
                    case .markdown: return "markdown"
                    case .error: return "error"
                    }
                }.joined(separator: ",")
                print("PARTIAL | \(relPath) | ext:\(ext) | UTI:\(uti) | Subtitle:\(doc.subtitle ?? "none") | Warn:[\(warns)] | Blocks:[\(blockTypes)] | Provider:\(doc.metadata.first(where: { $0.key == "Provider" })?.value ?? "none")")
            case .unsupported(let reason):
                print("UNSUPPORTED | \(relPath) | ext:\(ext) | UTI:\(uti) | Reason:\(reason)")
            case .failed(let err):
                print("FAILED | \(relPath) | ext:\(ext) | UTI:\(uti) | Reason:\(err.reason) - \(err.message)")
            }
        }
    }
}
