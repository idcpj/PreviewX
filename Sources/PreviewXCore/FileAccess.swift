import Foundation
import UniformTypeIdentifiers

public enum FileAccess {
    public static func identity(for url: URL) throws -> FileIdentity {
        let values = try url.resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey,
            .contentTypeKey,
            .isRegularFileKey
        ])

        guard values.isRegularFile != false else {
            throw PreviewError(.unsupported, "Only regular files can be previewed.")
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value
            ?? UInt64(values.fileSize ?? 0)

        return FileIdentity(
            url: url,
            size: size,
            modifiedAt: values.contentModificationDate,
            contentTypeIdentifier: values.contentType?.identifier
        )
    }

    public static func read(
        _ url: URL,
        offset: UInt64 = 0,
        length: Int,
        budget: ResourceBudget,
        resourceTracker: PreviewResourceTracker? = nil
    ) async throws -> Data {
        try Task.checkCancellation()
        guard length >= 0 else {
            throw PreviewError(.unknown, "Requested read length cannot be negative.")
        }
        guard UInt64(length) <= budget.maxBytesRead else {
            throw PreviewError(.tooLarge, "The requested region exceeds the preview read budget.")
        }
        if let resourceTracker {
            try await resourceTracker.reserve(UInt64(length))
        }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: offset)
            let data = try handle.read(upToCount: length) ?? Data()
            try Task.checkCancellation()
            return data
        } catch is CancellationError {
            throw PreviewError(.timeout, "Preview was cancelled.")
        } catch let error as PreviewError {
            throw error
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            throw PreviewError(.unsupported, "The file is no longer available.")
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            throw PreviewError(.permissionDenied, "PreviewX does not have permission to read this file.")
        } catch {
            throw PreviewError(.unknown, "Unable to read this file safely: \(error.localizedDescription)")
        }
    }
}

public struct FileClassifier: Sendable {
    public init() {}

    public func classify(
        identity: FileIdentity,
        budget: ResourceBudget,
        resourceTracker: PreviewResourceTracker? = nil
    ) async throws -> FileClassification {
        let extensionValue = identity.url.pathExtension.lowercased()
        var evidence: [ClassificationEvidence] = []
        var signatures = Set<String>()

        if let contentTypeIdentifier = identity.contentTypeIdentifier {
            evidence.append(.init(kind: .declaredType, value: contentTypeIdentifier, confidence: 1.0))
        }

        if !extensionValue.isEmpty {
            evidence.append(.init(kind: .filenameExtension, value: extensionValue, confidence: 0.7))
        }

        let headLength = Int(min(identity.size, min(budget.maxBytesRead, 8 * 1_024)))
        if headLength > 0 {
            let head = try await FileAccess.read(
                identity.url,
                length: headLength,
                budget: budget,
                resourceTracker: resourceTracker
            )
            signatures = signaturesForHead(head)
            if ["vue", "svelte", "html", "htm"].contains(extensionValue) {
                signatures.remove("xml-like")
            }
            evidence.append(contentsOf: signatures.sorted().map {
                ClassificationEvidence(kind: .signature, value: $0, confidence: 0.8)
            })
        }

        let derivedType: String?
        if ["md", "markdown", "mdown"].contains(extensionValue) {
            derivedType = "net.daringfireball.markdown"
        } else if let type = identity.contentTypeIdentifier, !type.hasPrefix("dyn.") && !type.contains("unknown") {
            derivedType = type
        } else if let type = UTType(filenameExtension: extensionValue) {
            derivedType = type.identifier
        } else if extensionValue == "jar" {
            derivedType = "com.sun.java-archive"
        } else if ["war", "apk", "wasm", "cmake"].contains(extensionValue) {
            derivedType = "com.previewx.\(extensionValue)"
        } else {
            derivedType = identity.contentTypeIdentifier
        }

        let confidence = evidence.map(\.confidence).max() ?? 0.1
        return FileClassification(
            contentTypeIdentifier: derivedType,
            filenameExtension: extensionValue.isEmpty ? nil : extensionValue,
            signatures: signatures,
            confidence: confidence,
            evidence: evidence
        )
    }

    private func signaturesForHead(_ data: Data) -> Set<String> {
        var signatures = Set<String>()
        let bytes = [UInt8](data.prefix(512))
        let trimmed = String(decoding: data.prefix(512), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]) || bytes.starts(with: [0x50, 0x4B, 0x05, 0x06]) {
            signatures.insert("zip")
        }
        if bytes.starts(with: [0x1F, 0x8B]) {
            signatures.insert("gzip")
        }
        if bytes.starts(with: [0x42, 0x5A, 0x68]) {
            signatures.insert("bzip2")
        }
        if bytes.starts(with: [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) {
            signatures.insert("xz")
        }
        if bytes.starts(with: [0x00, 0x61, 0x73, 0x6D]) {
            signatures.insert("wasm")
        }
        if bytes.starts(with: [0x7F, 0x45, 0x4C, 0x46]) {
            signatures.insert("elf")
        }
        if bytes.starts(with: [0xFE, 0xED, 0xFA, 0xCE]) || bytes.starts(with: [0xFE, 0xED, 0xFA, 0xCF]) ||
           bytes.starts(with: [0xCE, 0xFA, 0xED, 0xFE]) || bytes.starts(with: [0xCF, 0xFA, 0xED, 0xFE]) ||
           bytes.starts(with: [0xCA, 0xFE, 0xBA, 0xBE]) {
            signatures.insert("macho")
        }
        if bytes.starts(with: [0x62, 0x70, 0x6C, 0x69, 0x73, 0x74]) {
            signatures.insert("bplist")
        }
        if bytes.starts(with: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) {
            signatures.insert("7z")
        }
        if String(decoding: bytes.prefix(16), as: UTF8.self).hasPrefix("SQLite format 3") {
            signatures.insert("sqlite")
        }
        if bytes.count >= 262 && Array(bytes[257...261]) == Array("ustar".utf8) {
            signatures.insert("tar")
        }
        if looksLikeJSON(trimmed) {
            signatures.insert("json-like")
        }
        if trimmed.hasPrefix("<?xml") {
            signatures.insert("xml-like")
        } else if trimmed.hasPrefix("<") {
            let lower = trimmed.lowercased()
            if !lower.hasPrefix("<?php") && !lower.hasPrefix("<!doctype html") && !lower.hasPrefix("<html") && !lower.hasPrefix("<template") && !lower.hasPrefix("<script") {
                signatures.insert("xml-like")
            }
        }
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            signatures.insert("utf8-bom")
        }
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) {
            signatures.insert("utf16-bom")
        }
        if bytes.contains(0) && !signatures.contains("utf16-bom") {
            signatures.insert("binary")
        } else if !bytes.isEmpty {
            signatures.insert("text-like")
        }
        return signatures
    }

    private func looksLikeJSON(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        if first == "{" { return true }
        guard first == "[" else { return false }
        let remainder = text.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = remainder.first else { return true }
        if token == "]" || token == "\"" || token == "{" || token == "[" || token == "-" {
            return true
        }
        return token.isNumber || token == "t" || token == "f" || token == "n"
    }
}

public struct DecodedText: Sendable {
    public let content: String
    public let encodingName: String
    public let wasTruncated: Bool
    public let byteCount: Int

    public init(content: String, encodingName: String, wasTruncated: Bool, byteCount: Int) {
        self.content = content
        self.encodingName = encodingName
        self.wasTruncated = wasTruncated
        self.byteCount = byteCount
    }
}

public enum TextDecoding {
    public static func readPreview(
        identity: FileIdentity,
        budget: ResourceBudget,
        resourceTracker: PreviewResourceTracker? = nil
    ) async throws -> DecodedText {
        let remaining = await resourceTracker?.remainingBytes() ?? budget.maxBytesRead
        let allowedBytes = min(identity.size, min(budget.maxBytesRead, remaining))
        guard allowedBytes > 0 || identity.size == 0 else {
            throw PreviewError(.tooLarge, "The preview budget was consumed before text content could be read.")
        }
        let data = try await FileAccess.read(
            identity.url,
            length: Int(min(allowedBytes, UInt64(Int.max))),
            budget: budget,
            resourceTracker: resourceTracker
        )
        let (text, encoding) = decode(data)
        return DecodedText(
            content: text,
            encodingName: encoding,
            wasTruncated: identity.size > UInt64(data.count),
            byteCount: data.count
        )
    }

    public static func decode(_ data: Data) -> (String, String) {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            let stripped = data.dropFirst(3)
            let text = String(data: stripped, encoding: .utf8) ?? String(decoding: stripped, as: UTF8.self)
            return (text, "UTF-8 (BOM)")
        }

        let candidates: [(String.Encoding, String)] = [
            (.utf8, "UTF-8"),
            (.utf16LittleEndian, "UTF-16 LE"),
            (.utf16BigEndian, "UTF-16 BE"),
            (.unicode, "UTF-16"),
            (.isoLatin1, "ISO-8859-1"),
            (.windowsCP1252, "Windows-1252")
        ]

        for (encoding, name) in candidates {
            if let text = String(data: data, encoding: encoding) {
                return (text, name)
            }
        }
        return (String(decoding: data, as: UTF8.self), "UTF-8 (lossy)")
    }
}
