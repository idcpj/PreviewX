import Foundation
import PreviewXCore

enum ProviderSupport {
    static func fileExtension(_ request: PreviewRequest) -> String {
        request.classification?.filenameExtension ?? request.identity.url.pathExtension.lowercased()
    }

    static func signatures(_ request: PreviewRequest) -> Set<String> {
        request.classification?.signatures ?? []
    }

    static func metadata(
        request: PreviewRequest,
        provider: ProviderDescriptor,
        encoding: String? = nil,
        extra: [MetadataItem] = []
    ) -> [MetadataItem] {
        var items = [
            MetadataItem("Type", request.classification?.contentTypeIdentifier ?? "Unknown"),
            MetadataItem("Size", ByteFormatHelper.format(request.identity.size)),
            MetadataItem("Provider", provider.name)
        ]
        if let encoding {
            items.append(MetadataItem("Encoding", encoding))
        }
        items.append(contentsOf: extra)
        return items
    }

    static func truncateLines(_ content: String, maximum: UInt64) -> (content: String, wasTruncated: Bool) {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard UInt64(lines.count) > maximum else { return (content, false) }
        let selected = lines.prefix(Int(min(maximum, UInt64(Int.max))))
        return (selected.joined(separator: "\n"), true)
    }

    static func textWarnings(decoded: DecodedText, linesTruncated: Bool) -> [PreviewWarning] {
        var warnings: [PreviewWarning] = []
        if decoded.wasTruncated {
            warnings.append(.init(kind: .truncated, message: "Only the first \(decoded.byteCount.formatted()) bytes were loaded within the preview budget."))
        }
        if linesTruncated {
            warnings.append(.init(kind: .truncated, message: "Only the first preview lines are shown."))
        }
        if decoded.encodingName.contains("lossy") {
            warnings.append(.init(kind: .encoding, message: "The file could not be decoded exactly; the raw bytes were rendered with a lossy UTF-8 fallback."))
        }
        return warnings
    }

    static func secretWarnings(content: String, policy: PreviewPolicy) -> [PreviewWarning] {
        guard policy.redactSecrets else { return [] }
        let findings = SecretDetector.findings(in: content)
        guard !findings.isEmpty else { return [] }
        let lines = findings.map { "\($0.line)" }.joined(separator: ", ")
        let kinds = Array(Set(findings.map(\.kind.rawValue))).sorted().joined(separator: ", ")
        return [PreviewWarning(
            kind: .security,
            message: "Potential \(kinds) detected at line \(lines). The original preview remains read-only and no content was sent externally."
        )]
    }

    static func isLikelyText(_ request: PreviewRequest) -> Bool {
        let classification = request.classification
        if let type = classification?.contentTypeIdentifier, type.contains("text") || type.contains("source") {
            return true
        }
        let signatures = classification?.signatures ?? []
        return signatures.contains("text-like") || signatures.contains("utf8-bom") || signatures.contains("utf16-bom")
    }
}

public struct LanguageDefinition: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let extensions: Set<String>
    public let filenames: Set<String>

    public init(id: String, displayName: String, extensions: Set<String>, filenames: Set<String> = []) {
        self.id = id
        self.displayName = displayName
        self.extensions = extensions
        self.filenames = filenames
    }
}

public enum LanguageCatalog {
    public static let definitions: [LanguageDefinition] = [
        .init(id: "swift", displayName: "Swift", extensions: ["swift"]),
        .init(id: "objective-c", displayName: "Objective-C", extensions: ["m", "mm", "h"]),
        .init(id: "c", displayName: "C", extensions: ["c", "cc", "cpp", "cxx", "hpp"]),
        .init(id: "rust", displayName: "Rust", extensions: ["rs"]),
        .init(id: "go", displayName: "Go", extensions: ["go"]),
        .init(id: "python", displayName: "Python", extensions: ["py", "pyw"]),
        .init(id: "javascript", displayName: "JavaScript", extensions: ["js", "mjs", "cjs", "jsx"]),
        .init(id: "typescript", displayName: "TypeScript", extensions: ["ts", "tsx"]),
        .init(id: "java", displayName: "Java", extensions: ["java"]),
        .init(id: "kotlin", displayName: "Kotlin", extensions: ["kt", "kts"]),
        .init(id: "sql", displayName: "SQL", extensions: ["sql", "ddl", "dml"]),
        .init(id: "makefile", displayName: "Makefile", extensions: ["mk", "mak"], filenames: ["makefile", "gnumakefile"]),
        .init(id: "shell", displayName: "Shell", extensions: ["sh", "bash", "zsh", "fish"]),
        .init(id: "php", displayName: "PHP", extensions: ["php", "php3", "php4", "php5", "php7", "phtml", "ph3", "ph4"]),
        .init(id: "ruby", displayName: "Ruby", extensions: ["rb", "rbw", "rake", "gemspec"], filenames: ["gemfile", "rakefile", "podfile", "brewfile"]),
        .init(id: "lua", displayName: "Lua", extensions: ["lua"]),
        .init(id: "perl", displayName: "Perl", extensions: ["pl", "pm", "pod", "t"]),
        .init(id: "r", displayName: "R", extensions: ["r", "rmd"]),
        .init(id: "scala", displayName: "Scala", extensions: ["scala", "sc"]),
        .init(id: "dart", displayName: "Dart", extensions: ["dart"]),
        .init(id: "csharp", displayName: "C#", extensions: ["cs"]),
        .init(id: "haskell", displayName: "Haskell", extensions: ["hs", "lhs"]),
        .init(id: "elixir", displayName: "Elixir", extensions: ["ex", "exs", "eex"]),
        .init(id: "erlang", displayName: "Erlang", extensions: ["erl", "hrl"]),
        .init(id: "clojure", displayName: "Clojure", extensions: ["clj", "cljs", "cljc", "edn"]),
        .init(id: "groovy", displayName: "Groovy", extensions: ["groovy", "gradle"]),
        .init(id: "powershell", displayName: "PowerShell", extensions: ["ps1", "psm1", "psd1"]),
        .init(id: "batch", displayName: "Batch", extensions: ["bat", "cmd"]),
        .init(id: "vue", displayName: "Vue", extensions: ["vue"]),
        .init(id: "svelte", displayName: "Svelte", extensions: ["svelte"]),
        .init(id: "graphql", displayName: "GraphQL", extensions: ["graphql", "gql"]),
        .init(id: "proto", displayName: "Protocol Buffers", extensions: ["proto"]),
        .init(id: "cmake", displayName: "CMake", extensions: ["cmake"], filenames: ["cmakelists.txt", "cmakelists"]),
        .init(id: "html", displayName: "HTML", extensions: ["html", "htm"]),
        .init(id: "css", displayName: "CSS", extensions: ["css", "scss", "sass", "less"]),
        .init(id: "dockerfile", displayName: "Dockerfile", extensions: ["dockerfile"], filenames: ["dockerfile", "containerfile"]),
        .init(id: "dotenv", displayName: "dotenv", extensions: ["env"], filenames: [".env"]),
        .init(id: "ini", displayName: "INI", extensions: ["ini", "cfg", "conf"]),
        .init(id: "diff", displayName: "Diff", extensions: ["diff", "patch"]),
        .init(id: "json", displayName: "JSON", extensions: ["json", "jsonc", "json5", "geojson", "har", "jsonl", "ndjson"]),
        .init(id: "markdown", displayName: "Markdown", extensions: ["md", "markdown", "mdown"]),
        .init(id: "lockfile", displayName: "Lockfile", extensions: ["lock"], filenames: ["yarn.lock", "cargo.lock", "podfile.lock", "package-lock.json", "composer.lock"]),
        .init(id: "plaintext", displayName: "Plain Text", extensions: ["txt", "text"], filenames: [".gitignore", ".gitattributes", ".editorconfig", ".npmignore", "license"])
    ]

    public static func definition(for url: URL) -> LanguageDefinition? {
        let filename = url.lastPathComponent.lowercased()
        let extensionValue = url.pathExtension.lowercased()
        return definitions.first { definition in
            definition.extensions.contains(extensionValue) || definition.filenames.contains(filename)
        }
    }
}
