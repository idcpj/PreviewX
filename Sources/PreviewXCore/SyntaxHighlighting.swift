import Foundation

/// Semantic token categories emitted by ``SyntaxHighlighter``.
///
/// The UI layer maps these to colors; the CLI can render them as plain text.
/// Keeping this in `PreviewXCore` lets both the SwiftUI app and headless tests
/// assert on real highlighting instead of duplicating a heuristic in the view.
public enum SyntaxTokenKind: String, Codable, Equatable, Sendable {
    case plain
    case keyword
    case type
    case string
    case number
    case comment
    case function
    case attribute
    case punctuation
}

public struct SyntaxToken: Equatable, Sendable {
    public let text: String
    public let kind: SyntaxTokenKind

    public init(text: String, kind: SyntaxTokenKind) {
        self.text = text
        self.kind = kind
    }
}

/// Deterministic, dependency-free syntax highlighter.
///
/// It is intentionally line-oriented so callers can highlight a single visible
/// line without re-parsing the whole document. Language rules cover the
/// keyword/comment conventions of the languages exercised by the mock fixtures
/// (php, sql, swift, python, html, and the C family) and degrade gracefully to
/// generic highlighting for anything else.
public enum SyntaxHighlighter {
    public static func tokens(in line: String, language: String?) -> [SyntaxToken] {
        let lang = (language ?? "").lowercased()
        if lang == "diff" || lang == "patch" {
            return tokenizeDiff(line)
        }
        if lang == "log" || lang == "logs" {
            return tokenizeLog(line)
        }
        let rules = LanguageRules.rules(for: language)
        return tokenize(line, rules: rules)
    }

    private static func tokenizeDiff(_ line: String) -> [SyntaxToken] {
        guard !line.isEmpty else { return [] }
        if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff --git")
            || line.hasPrefix("index ") || line.hasPrefix("new file") || line.hasPrefix("deleted file")
            || line.hasPrefix("similarity index") || line.hasPrefix("rename ") || line.hasPrefix("commit ")
            || line.hasPrefix("Author:") || line.hasPrefix("Date:") {
            return [SyntaxToken(text: line, kind: .comment)]
        }
        if line.hasPrefix("@@") {
            return [SyntaxToken(text: line, kind: .keyword)]
        }
        if line.hasPrefix("+") {
            return [SyntaxToken(text: line, kind: .string)]
        }
        if line.hasPrefix("-") {
            return [SyntaxToken(text: line, kind: .attribute)]
        }
        return [SyntaxToken(text: line, kind: .plain)]
    }

    private static func tokenizeLog(_ line: String) -> [SyntaxToken] {
        guard !line.isEmpty else { return [] }
        var tokens: [SyntaxToken] = []
        let characters = Array(line)
        var index = 0

        while index < characters.count {
            let ch = characters[index]

            // 1. Quoted string: "..."
            if ch == "\"" || ch == "'" {
                let quote = ch
                var str = String(quote)
                index += 1
                while index < characters.count {
                    let next = characters[index]
                    str.append(next)
                    index += 1
                    if next == quote { break }
                    if next == "\\" && index < characters.count {
                        str.append(characters[index])
                        index += 1
                    }
                }
                tokens.append(SyntaxToken(text: str, kind: .string))
                continue
            }

            // 2. Bracketed metadata: [...]
            if ch == "[" {
                var bracketed = "["
                index += 1
                while index < characters.count {
                    let next = characters[index]
                    bracketed.append(next)
                    index += 1
                    if next == "]" { break }
                }
                let inner = bracketed.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
                let upper = inner.uppercased()
                if upper == "ERROR" || upper == "FATAL" || upper == "CRITICAL" {
                    tokens.append(SyntaxToken(text: bracketed, kind: .attribute))
                } else if upper == "WARN" || upper == "WARNING" {
                    tokens.append(SyntaxToken(text: bracketed, kind: .type))
                } else if upper == "INFO" || upper == "NOTICE" {
                    tokens.append(SyntaxToken(text: bracketed, kind: .function))
                } else if upper == "DEBUG" || upper == "TRACE" {
                    tokens.append(SyntaxToken(text: bracketed, kind: .comment))
                } else {
                    tokens.append(SyntaxToken(text: bracketed, kind: .attribute))
                }
                continue
            }

            // 3. Word token (alphanumeric, -, _, ., :, /)
            if ch.isLetter || ch.isNumber || ch == "_" || ch == "-" || ch == "." || ch == ":" {
                var word = ""
                while index < characters.count {
                    let next = characters[index]
                    if next.isWhitespace || next == "\"" || next == "'" || next == "[" || next == "]" || next == "(" || next == ")" || next == "," {
                        break
                    }
                    word.append(next)
                    index += 1
                }
                let upper = word.uppercased()
                if upper == "ERROR" || upper == "FATAL" || upper == "CRITICAL" {
                    tokens.append(SyntaxToken(text: word, kind: .attribute))
                } else if upper == "WARN" || upper == "WARNING" {
                    tokens.append(SyntaxToken(text: word, kind: .type))
                } else if upper == "INFO" || upper == "NOTICE" {
                    tokens.append(SyntaxToken(text: word, kind: .function))
                } else if upper == "DEBUG" || upper == "TRACE" {
                    tokens.append(SyntaxToken(text: word, kind: .comment))
                } else if ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"].contains(upper) {
                    tokens.append(SyntaxToken(text: word, kind: .keyword))
                } else if word.contains(":") && (word.contains("-") || word.hasSuffix("Z")) {
                    tokens.append(SyntaxToken(text: word, kind: .number))
                } else if isIPAddress(word) {
                    tokens.append(SyntaxToken(text: word, kind: .type))
                } else if isNumber(word) {
                    tokens.append(SyntaxToken(text: word, kind: .number))
                } else {
                    tokens.append(SyntaxToken(text: word, kind: .plain))
                }
                continue
            }

            // 4. Any other symbol or whitespace
            tokens.append(SyntaxToken(text: String(ch), kind: .plain))
            index += 1
        }

        return tokens.isEmpty ? [SyntaxToken(text: line, kind: .plain)] : tokens
    }

    private static func isIPAddress(_ word: String) -> Bool {
        let parts = word.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { Int($0) != nil }
    }

    // MARK: - Language rules

    struct LanguageRules {
        var keywords: Set<String>
        var types: Set<String>
        var lineComment: [String]
        var stringDelimiters: Set<Character>
        var markup: Bool

        static func rules(for language: String?) -> LanguageRules {
            switch (language ?? "").lowercased() {
            case "swift":
                return LanguageRules(
                    keywords: ["let", "var", "func", "struct", "class", "enum", "protocol", "extension", "import",
                               "return", "if", "else", "for", "while", "guard", "switch", "case", "default", "in",
                               "public", "private", "internal", "fileprivate", "open", "static", "final", "async",
                               "await", "throws", "throw", "try", "do", "catch", "defer", "self", "init", "deinit",
                               "true", "false", "nil", "some", "any", "where", "as", "is", "typealias"],
                    types: ["Int", "String", "Double", "Float", "Bool", "Array", "Dictionary", "Set", "Data", "URL",
                            "Optional", "Result", "UUID", "Void"],
                    lineComment: ["//"],
                    stringDelimiters: ["\""],
                    markup: false
                )
            case "python":
                return LanguageRules(
                    keywords: ["def", "class", "return", "if", "elif", "else", "for", "while", "import", "from",
                               "as", "with", "try", "except", "finally", "raise", "pass", "break", "continue",
                               "lambda", "yield", "global", "nonlocal", "assert", "del", "in", "is", "not", "and",
                               "or", "None", "True", "False", "self", "async", "await"],
                    types: ["int", "str", "float", "bool", "list", "dict", "set", "tuple", "bytes", "object"],
                    lineComment: ["#"],
                    stringDelimiters: ["\"", "'"],
                    markup: false
                )
            case "php":
                return LanguageRules(
                    keywords: ["function", "class", "public", "private", "protected", "return", "if", "else",
                               "elseif", "foreach", "for", "while", "do", "switch", "case", "default", "break",
                               "continue", "new", "echo", "print", "namespace", "use", "extends", "implements",
                               "interface", "trait", "static", "const", "abstract", "final", "try", "catch",
                               "finally", "throw", "true", "false", "null", "array", "as", "instanceof", "global"],
                    types: ["int", "string", "float", "bool", "array", "object", "void", "self", "mixed", "callable"],
                    lineComment: ["//", "#"],
                    stringDelimiters: ["\"", "'"],
                    markup: false
                )
            case "sql":
                return LanguageRules(
                    keywords: ["select", "from", "where", "insert", "into", "values", "update", "set", "delete",
                               "create", "table", "drop", "alter", "add", "index", "view", "join", "inner", "left",
                               "right", "outer", "full", "on", "as", "and", "or", "not", "null", "is", "in", "like",
                               "between", "order", "by", "group", "having", "limit", "offset", "distinct", "union",
                               "all", "primary", "key", "foreign", "references", "default", "unique", "constraint",
                               "begin", "commit", "rollback", "case", "when", "then", "else", "end"],
                    types: ["int", "integer", "varchar", "char", "text", "boolean", "date", "datetime", "timestamp",
                            "real", "float", "double", "decimal", "numeric", "blob", "serial", "bigint", "smallint"],
                    lineComment: ["--"],
                    stringDelimiters: ["'", "\""],
                    markup: false
                )
            case "html", "xml", "svg", "vue", "svelte":
                return LanguageRules(
                    keywords: [],
                    types: [],
                    lineComment: [],
                    stringDelimiters: ["\"", "'"],
                    markup: true
                )
            case "dockerfile":
                return LanguageRules(
                    keywords: ["FROM", "RUN", "CMD", "LABEL", "EXPOSE", "ENV", "ADD", "COPY",
                               "ENTRYPOINT", "VOLUME", "USER", "WORKDIR", "ARG", "ONBUILD",
                               "STOPSIGNAL", "HEALTHCHECK", "SHELL", "AS",
                               "from", "run", "cmd", "label", "expose", "env", "add", "copy",
                               "entrypoint", "volume", "user", "workdir", "arg", "as"],
                    types: [],
                    lineComment: ["#"],
                    stringDelimiters: ["\"", "'"],
                    markup: false
                )
            case "cmake", "cmakelists", "cmakelists.txt":
                return LanguageRules(
                    keywords: ["cmake_minimum_required", "project", "add_executable", "add_library",
                               "target_link_libraries", "target_include_directories", "find_package",
                               "set", "if", "else", "endif", "message", "option", "include",
                               "enable_testing", "add_test", "add_subdirectory", "install"],
                    types: [],
                    lineComment: ["#"],
                    stringDelimiters: ["\""],
                    markup: false
                )
            case "graphql":
                return LanguageRules(
                    keywords: ["type", "query", "mutation", "subscription", "schema", "fragment", "on",
                               "enum", "input", "interface", "union", "scalar", "implements", "directive",
                               "extend", "true", "false", "null"],
                    types: ["String", "Int", "Float", "Boolean", "ID"],
                    lineComment: ["#"],
                    stringDelimiters: ["\""],
                    markup: false
                )
            case "proto", "protobuf":
                return LanguageRules(
                    keywords: ["syntax", "message", "enum", "service", "rpc", "returns", "package",
                               "import", "option", "repeated", "optional", "required", "reserved",
                               "extensions", "to", "max", "map"],
                    types: ["double", "float", "int32", "int64", "uint32", "uint64", "sint32", "sint64",
                            "fixed32", "fixed64", "sfixed32", "sfixed64", "bool", "string", "bytes"],
                    lineComment: ["//"],
                    stringDelimiters: ["\"", "'"],
                    markup: false
                )
            case "css", "scss", "sass", "less":
                return LanguageRules(
                    keywords: ["@import", "@media", "@keyframes", "@font-face", "@supports",
                               "!important", "from", "to", "root"],
                    types: [],
                    lineComment: ["//", "/*"],
                    stringDelimiters: ["\"", "'"],
                    markup: false
                )
            case "c", "objective-c", "java", "go", "rust", "javascript", "typescript", "kotlin",
                 "csharp", "scala", "dart", "groovy", "gradle":
                return LanguageRules(
                    keywords: ["int", "long", "short", "char", "float", "double", "void", "bool", "boolean",
                               "return", "if", "else", "for", "while", "do", "switch", "case", "default", "break",
                               "continue", "struct", "class", "enum", "interface", "public", "private", "protected",
                               "static", "final", "const", "let", "var", "func", "fn", "def", "import", "package",
                               "new", "delete", "try", "catch", "finally", "throw", "throws", "async", "await",
                               "true", "false", "null", "nil", "nullptr", "this", "self", "super", "extends",
                               "implements", "namespace", "using", "typedef", "type", "func", "go", "defer",
                               "match", "impl", "trait", "mut", "pub", "fn", "where", "plugins", "dependencies",
                               "repositories"],
                    types: ["String", "Int", "Integer", "Long", "Double", "Float", "Boolean", "Object", "List",
                            "Map", "Array", "Vec", "Option", "Result"],
                    lineComment: ["//"],
                    stringDelimiters: ["\"", "'", "`"],
                    markup: false
                )
            case "ruby", "gemfile", "rakefile", "podfile", "brewfile":
                return LanguageRules(
                    keywords: ["def", "end", "class", "module", "if", "elsif", "else", "unless", "while", "until",
                               "for", "in", "do", "return", "yield", "super", "self", "nil", "true", "false",
                               "require", "require_relative", "include", "extend", "attr_accessor", "attr_reader",
                               "begin", "rescue", "ensure", "raise", "pod", "gem", "tap", "brew", "target"],
                    types: ["String", "Integer", "Float", "Array", "Hash", "Symbol"],
                    lineComment: ["#"],
                    stringDelimiters: ["\"", "'"],
                    markup: false
                )
            case "perl":
                return LanguageRules(
                    keywords: ["my", "our", "local", "sub", "use", "require", "package", "if", "elsif", "else",
                               "unless", "while", "until", "for", "foreach", "return", "last", "next", "redo",
                               "die", "warn", "print", "strict", "warnings"],
                    types: ["SCALAR", "ARRAY", "HASH"],
                    lineComment: ["#"],
                    stringDelimiters: ["\"", "'"],
                    markup: false
                )
            case "r":
                return LanguageRules(
                    keywords: ["function", "if", "else", "repeat", "while", "for", "in", "next", "break",
                               "TRUE", "FALSE", "NULL", "Inf", "NaN", "NA", "return", "library", "require"],
                    types: ["numeric", "character", "logical", "matrix", "data.frame", "list", "vector"],
                    lineComment: ["#"],
                    stringDelimiters: ["\"", "'"],
                    markup: false
                )
            case "elixir":
                return LanguageRules(
                    keywords: ["defmodule", "def", "defp", "do", "end", "import", "require", "alias", "use",
                               "if", "unless", "case", "cond", "with", "fn", "true", "false", "nil"],
                    types: ["String", "Integer", "Float", "List", "Map", "Tuple", "Atom"],
                    lineComment: ["#"],
                    stringDelimiters: ["\"", "'"],
                    markup: false
                )
            case "erlang":
                return LanguageRules(
                    keywords: ["-module", "-export", "-include", "fun", "case", "of", "if", "begin", "end",
                               "receive", "after", "catch", "try", "when", "true", "false"],
                    types: ["integer", "float", "atom", "binary", "list", "tuple", "pid"],
                    lineComment: ["%"],
                    stringDelimiters: ["\"", "'"],
                    markup: false
                )
            case "clojure":
                return LanguageRules(
                    keywords: ["def", "defn", "defn-", "fn", "let", "if", "do", "when", "cond", "loop", "recur",
                               "ns", "require", "use", "import", "nil", "true", "false"],
                    types: ["String", "Long", "Double", "Boolean", "Vector", "Map", "Set", "List"],
                    lineComment: [";"],
                    stringDelimiters: ["\""],
                    markup: false
                )
            case "haskell":
                return LanguageRules(
                    keywords: ["module", "where", "import", "let", "in", "case", "of", "if", "then", "else",
                               "data", "type", "newtype", "class", "instance", "deriving", "do", "return"],
                    types: ["Int", "Integer", "Float", "Double", "Char", "String", "Bool", "Maybe", "Either", "IO"],
                    lineComment: ["--"],
                    stringDelimiters: ["\"", "'"],
                    markup: false
                )
            case "powershell", "ps1":
                return LanguageRules(
                    keywords: ["function", "param", "if", "else", "elseif", "switch", "foreach", "for", "while",
                               "do", "until", "break", "continue", "return", "try", "catch", "finally", "throw",
                               "Write-Host", "Write-Output", "Get-ChildItem", "Set-Variable", "Get-Content"],
                    types: ["string", "int", "bool", "array", "hashtable"],
                    lineComment: ["#"],
                    stringDelimiters: ["\"", "'"],
                    markup: false
                )
            case "batch", "cmd", "bat":
                return LanguageRules(
                    keywords: ["echo", "off", "on", "set", "if", "else", "goto", "call", "exit", "pause",
                               "for", "in", "do", "shift", "cls", "rem"],
                    types: [],
                    lineComment: ["rem", "::"],
                    stringDelimiters: ["\""],
                    markup: false
                )
            case "shell", "bash", "zsh", "fish", "makefile", "yaml", "toml", "ini", "dotenv", "conf", "cfg":
                return LanguageRules(
                    keywords: ["if", "then", "else", "elif", "fi", "for", "in", "do", "done", "while", "case",
                               "esac", "function", "return", "export", "local", "echo", "true", "false", "set"],
                    types: [],
                    lineComment: ["#"],
                    stringDelimiters: ["\"", "'"],
                    markup: false
                )
            default:
                return LanguageRules(
                    keywords: ["let", "var", "func", "function", "def", "fn", "class", "struct", "enum", "import",
                               "return", "if", "else", "for", "while", "public", "private", "async", "await",
                               "true", "false", "null", "nil", "package"],
                    types: [],
                    lineComment: ["//", "#"],
                    stringDelimiters: ["\"", "'"],
                    markup: false
                )
            }
        }
    }

    // MARK: - Tokenizer

    private static func tokenize(_ line: String, rules: LanguageRules) -> [SyntaxToken] {
        if rules.markup {
            return tokenizeMarkup(line)
        }

        // Split off a trailing line comment first.
        var source = line
        var commentToken: SyntaxToken?
        for marker in rules.lineComment {
            if let range = source.range(of: marker) {
                // Avoid treating "://" (URLs) as comments for `//` markers.
                if marker == "//", range.lowerBound > source.startIndex,
                   source[source.index(before: range.lowerBound)] == ":" {
                    continue
                }
                commentToken = SyntaxToken(text: String(source[range.lowerBound...]), kind: .comment)
                source = String(source[..<range.lowerBound])
                break
            }
        }

        var tokens: [SyntaxToken] = []
        var word = ""

        func flushWord(followedBy next: Character?) {
            guard !word.isEmpty else { return }
            let lowered = word.lowercased()
            let kind: SyntaxTokenKind
            if rules.keywords.contains(word) || rules.keywords.contains(lowered) {
                kind = .keyword
            } else if rules.types.contains(word) || rules.types.contains(lowered) {
                kind = .type
            } else if isNumber(word) {
                kind = .number
            } else if next == "(" {
                kind = .function
            } else {
                kind = .plain
            }
            tokens.append(SyntaxToken(text: word, kind: kind))
            word = ""
        }

        let iterator = Array(source)
        var index = 0
        var activeQuote: Character?
        var stringBuffer = ""

        while index < iterator.count {
            let character = iterator[index]

            if let quote = activeQuote {
                stringBuffer.append(character)
                if character == quote {
                    tokens.append(SyntaxToken(text: stringBuffer, kind: .string))
                    stringBuffer = ""
                    activeQuote = nil
                }
                index += 1
                continue
            }

            if rules.stringDelimiters.contains(character) {
                flushWord(followedBy: character)
                activeQuote = character
                stringBuffer = String(character)
                index += 1
                continue
            }

            if character.isLetter || character.isNumber || character == "_" || character == "." && !word.isEmpty && word.first!.isNumber {
                word.append(character)
                index += 1
                continue
            }

            let next = index + 1 < iterator.count ? iterator[index + 1] : nil
            flushWord(followedBy: character)
            let punctuationKind: SyntaxTokenKind = character.isWhitespace ? .plain : .punctuation
            tokens.append(SyntaxToken(text: String(character), kind: punctuationKind))
            _ = next
            index += 1
        }

        if activeQuote != nil {
            tokens.append(SyntaxToken(text: stringBuffer, kind: .string))
        } else {
            flushWord(followedBy: nil)
        }

        if let commentToken {
            tokens.append(commentToken)
        }
        return tokens.isEmpty ? [SyntaxToken(text: line, kind: .plain)] : tokens
    }

    private static func tokenizeMarkup(_ line: String) -> [SyntaxToken] {
        var tokens: [SyntaxToken] = []
        var buffer = ""
        var insideTag = false
        var activeQuote: Character?

        func flush(_ kind: SyntaxTokenKind) {
            guard !buffer.isEmpty else { return }
            tokens.append(SyntaxToken(text: buffer, kind: kind))
            buffer = ""
        }

        for character in line {
            if insideTag {
                if let quote = activeQuote {
                    buffer.append(character)
                    if character == quote {
                        flush(.string)
                        activeQuote = nil
                    }
                    continue
                }
                if character == "\"" || character == "'" {
                    flush(.keyword)
                    buffer.append(character)
                    activeQuote = character
                    continue
                }
                if character == ">" {
                    buffer.append(character)
                    flush(.keyword)
                    insideTag = false
                    continue
                }
                buffer.append(character)
            } else {
                if character == "<" {
                    flush(.plain)
                    buffer.append(character)
                    insideTag = true
                    continue
                }
                buffer.append(character)
            }
        }
        flush(insideTag ? .keyword : .plain)
        return tokens.isEmpty ? [SyntaxToken(text: line, kind: .plain)] : tokens
    }

    private static func isNumber(_ word: String) -> Bool {
        guard let first = word.first else { return false }
        if first.isNumber { return Double(word) != nil || word.allSatisfy { $0.isHexDigit || $0 == "x" || $0 == "." } }
        return false
    }
}
