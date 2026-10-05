import Foundation

public enum SensitiveContentKind: String, Codable, Sendable {
    case privateKey = "private key"
    case apiKey = "API key"
    case accessToken = "access token"
    case passwordAssignment = "password assignment"
    case bearerToken = "bearer token"
}

public struct SensitiveContentFinding: Equatable, Sendable {
    public let kind: SensitiveContentKind
    public let line: Int

    public init(kind: SensitiveContentKind, line: Int) {
        self.kind = kind
        self.line = line
    }
}

public enum SecretDetector {
    private static let rules: [(SensitiveContentKind, NSRegularExpression)] = [
        (.privateKey, expression("-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----")),
        (.apiKey, expression("\\bAKIA[0-9A-Z]{16}\\b")),
        (.accessToken, expression("(?i)[\"']?\\b(?:api[_-]?key|access[_-]?token|secret|token)[\"']?\\s*[:=]\\s*[\"']?[A-Za-z0-9_./+=-]{12,}")),
        (.passwordAssignment, expression("(?i)[\"']?\\b(?:password|passwd|pwd)[\"']?\\s*[:=]\\s*[^\\s#]{4,}")),
        (.bearerToken, expression("(?i)\\bBearer\\s+[A-Za-z0-9_./+=-]{12,}")),
        (.accessToken, expression("\\beyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\b"))
    ]

    public static func findings(in text: String, maximum: Int = 5) -> [SensitiveContentFinding] {
        guard maximum > 0 else { return [] }
        var findings: [SensitiveContentFinding] = []
        for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            guard findings.count < maximum else { break }
            let value = String(line)
            let range = NSRange(value.startIndex..., in: value)
            for (kind, expression) in rules where expression.firstMatch(in: value, range: range) != nil {
                findings.append(SensitiveContentFinding(kind: kind, line: offset + 1))
                break
            }
        }
        return findings
    }

    private static func expression(_ pattern: String) -> NSRegularExpression {
        // These literals are maintained with the source because the detector never records a match value.
        try! NSRegularExpression(pattern: pattern)
    }
}
