import Foundation
import PreviewXCore
import zlib
import SQLite3

public struct ArchiveProvider: PreviewProvider {
    public let descriptor = ProviderDescriptor(
        id: "com.previewx.archive",
        name: "Archive Inspector",
        supportedTypes: [
            "public.zip-archive",
            "public.tar-archive",
            "org.gnu.gnu-zip-archive",
            "com.sun.java-archive",
            "com.previewx.jar",
            "com.previewx.war",
            "com.previewx.apk"
        ],
        extensions: ["zip", "tar", "tgz", "gz", "gzip", "tar.gz", "7z", "jar", "war", "apk", "aar"],
        priority: 110,
        capabilities: [.tree]
    )

    public init() {}

    public func canPreview(_ request: PreviewRequest) async -> ProviderMatch {
        let ext = ProviderSupport.fileExtension(request)
        let filename = request.identity.filename.lowercased()
        if descriptor.extensions.contains(ext) || filename.hasSuffix(".tar.gz") {
            return .init(confidence: 700, specificity: 100, reason: "Archive extension")
        }
        let signatures = ProviderSupport.signatures(request)
        if !signatures.intersection(["zip", "tar", "gzip", "7z", "xz", "jar", "war", "apk"]).isEmpty {
            return .init(confidence: 800, specificity: 100, reason: "Archive signature")
        }
        return .noMatch
    }

    public func makePreview(_ request: PreviewRequest) async throws -> PreviewDocument {
        guard request.policy.allowArchiveInspection else {
            throw PreviewError(.securityPolicyViolation, "Archive inspection is disabled by the current security policy.")
        }
        return try await ArchiveInspector.inspect(request: request, descriptor: descriptor)
    }
}

public struct BinaryMetadataProvider: PreviewProvider {
    public let descriptor = ProviderDescriptor(
        id: "com.previewx.binary",
        name: "Binary Metadata",
        supportedTypes: ["public.data"],
        priority: 1,
        capabilities: [.raw]
    )

    public init() {}

    public func canPreview(_ request: PreviewRequest) async -> ProviderMatch {
        let signatures = ProviderSupport.signatures(request)
        if signatures.contains("elf") {
            return .init(confidence: 500, specificity: 80, reason: "ELF binary signature")
        }
        if signatures.contains("macho") {
            return .init(confidence: 500, specificity: 80, reason: "Mach-O binary signature")
        }
        if signatures.contains("wasm") {
            return .init(confidence: 500, specificity: 80, reason: "WebAssembly binary signature")
        }
        if signatures.contains("binary") {
            return .init(confidence: 100, specificity: 1, reason: "Bounded binary-content heuristic")
        }
        return .init(confidence: 10, specificity: 0, reason: "Deterministic binary fallback")
    }

    public func makePreview(_ request: PreviewRequest) async throws -> PreviewDocument {
        let data = try await FileAccess.read(
            request.identity.url,
            length: Int(min(512, request.policy.budget.maxBytesRead)),
            budget: request.policy.budget,
            resourceTracker: request.resourceTracker
        )
        let hexRows = data.enumerated().reduce(into: [String]()) { rows, element in
            let (index, byte) = element
            if index.isMultiple(of: 16) {
                rows.append(String(format: "%08X  %02X", index, byte))
            } else {
                rows[rows.count - 1] += String(format: " %02X", byte)
            }
        }

        var extraMetadata = [
            MetadataItem("Magic bytes", data.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")),
            MetadataItem("Read", "\(data.count) bytes")
        ]
        var warnings: [PreviewWarning] = []

        if data.starts(with: [0x7F, 0x45, 0x4C, 0x46]) {
            let is64 = data.count > 4 && data[4] == 2
            let isLE = data.count > 5 && data[5] == 1
            let arch = is64 ? "64-bit" : (data.count > 4 && data[4] == 1 ? "32-bit" : "Unknown")
            let endian = isLE ? "Little-endian" : "Big-endian"
            extraMetadata.insert(MetadataItem("Format", "ELF (\(arch), \(endian))"), at: 0)
            if data.count >= 18 {
                let typeCode = isLE ? ArchiveBytes.uint16LE(data, at: 16) : ArchiveBytes.uint16BE(data, at: 16)
                let typeStr: String
                switch typeCode {
                case 1: typeStr = "Relocatable object"
                case 2: typeStr = "Executable"
                case 3: typeStr = "Shared object / Dynamic library"
                case 4: typeStr = "Core dump"
                default: typeStr = "Type \(typeCode)"
                }
                extraMetadata.insert(MetadataItem("ELF type", typeStr), at: 1)
            }
        } else if data.starts(with: [0x00, 0x61, 0x73, 0x6D]) {
            let version = data.count >= 8 ? ArchiveBytes.uint32LE(data, at: 4) : 1
            extraMetadata.insert(MetadataItem("Format", "WebAssembly Module (WASM v\(version))"), at: 0)
        } else if data.starts(with: [0xFE, 0xED, 0xFA, 0xCE]) || data.starts(with: [0xFE, 0xED, 0xFA, 0xCF]) ||
                  data.starts(with: [0xCE, 0xFA, 0xED, 0xFE]) || data.starts(with: [0xCF, 0xFA, 0xED, 0xFE]) ||
                  data.starts(with: [0xCA, 0xFE, 0xBA, 0xBE]) {
            let is64 = data.starts(with: [0xFE, 0xED, 0xFA, 0xCF]) || data.starts(with: [0xCF, 0xFA, 0xED, 0xFE])
            let isUniversal = data.starts(with: [0xCA, 0xFE, 0xBA, 0xBE])
            let arch = isUniversal ? "Universal Fat Binary" : (is64 ? "64-bit Mach-O" : "32-bit Mach-O")
            extraMetadata.insert(MetadataItem("Format", arch), at: 0)
        }
        warnings.append(PreviewWarning(
            kind: .unsupportedFeature,
            message: "PreviewX did not identify a specialized renderer; only safe metadata and the first 512 bytes are shown."
        ))

        return PreviewDocument(
            title: request.identity.filename,
            subtitle: "Binary metadata",
            blocks: [
                .table(.init(
                    title: "Signature",
                    columns: ["Offset", "Hex bytes"],
                    rows: hexRows.enumerated().map { index, line in
                        let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
                        return [String(index * 16), parts.dropFirst().joined(separator: " ")]
                    }
                ))
            ],
            metadata: ProviderSupport.metadata(
                request: request,
                provider: descriptor,
                extra: extraMetadata
            ),
            capabilities: descriptor.capabilities,
            warnings: warnings
        )
    }
}

public struct SQLiteMetadataProvider: PreviewProvider {
    public let descriptor = ProviderDescriptor(
        id: "com.previewx.sqlite",
        name: "SQLite Metadata",
        supportedTypes: ["public.database"],
        extensions: ["sqlite", "sqlite3", "db"],
        priority: 105,
        capabilities: [.raw]
    )

    public init() {}

    public func canPreview(_ request: PreviewRequest) async -> ProviderMatch {
        if ProviderSupport.signatures(request).contains("sqlite") {
            return .init(confidence: 900, specificity: 100, reason: "SQLite signature")
        }
        let ext = ProviderSupport.fileExtension(request)
        if ext == "sqlite" || ext == "sqlite3" || ext == "db" {
            return .init(confidence: 800, specificity: 100, reason: "SQLite extension")
        }
        return .noMatch
    }

    public func makePreview(_ request: PreviewRequest) async throws -> PreviewDocument {
        let readLength = Int(min(100, request.policy.budget.maxBytesRead))
        let data = try await FileAccess.read(
            request.identity.url,
            length: readLength,
            budget: request.policy.budget,
            resourceTracker: request.resourceTracker
        )

        let isValidSQLite = String(decoding: data.prefix(16), as: UTF8.self).hasPrefix("SQLite format 3")
        if !isValidSQLite {
            let hexBytes = data.prefix(32).map { String(format: "%02X", $0) }.joined(separator: " ")
            let warning = PreviewWarning(
                kind: .malformed,
                message: "The file does not contain a valid SQLite 3 header signature."
            )
            return PreviewDocument(
                title: request.identity.filename,
                subtitle: "Corrupted SQLite Database",
                blocks: [
                    .error(.init(
                        title: "Malformed SQLite Database",
                        message: "The file header does not match the standard 'SQLite format 3' magic signature.",
                        recoverySuggestion: "Inspect the raw header bytes below or restore from a backup."
                    )),
                    .table(.init(
                        title: "Header Diagnostic",
                        columns: ["Offset", "Hex bytes"],
                        rows: [
                            ["0x0000", hexBytes.isEmpty ? "(empty file)" : hexBytes]
                        ]
                    ))
                ],
                metadata: ProviderSupport.metadata(request: request, provider: descriptor),
                capabilities: descriptor.capabilities,
                warnings: [warning]
            )
        }

        let pageSize = ArchiveBytes.uint16BE(data, at: 16)
        let effectivePageSize = pageSize == 1 ? 65_536 : Int(pageSize)
        let fileChangeCounter = data.count >= 28 ? ArchiveBytes.uint32BE(data, at: 24) : 0
        let schemaFormat = data.count > 44 ? data[44] : 0
        let textEncodingCode = data.count >= 60 ? ArchiveBytes.uint32BE(data, at: 56) : 1
        let textEncoding: String
        switch textEncodingCode {
        case 1: textEncoding = "UTF-8"
        case 2: textEncoding = "UTF-16le"
        case 3: textEncoding = "UTF-16be"
        default: textEncoding = "Unknown (\(textEncodingCode))"
        }
        let userVersion = data.count >= 64 ? ArchiveBytes.uint32BE(data, at: 60) : 0
        let version = data.count >= 100 ? ArchiveBytes.uint32BE(data, at: 96) : 0

        var rows: [[String]] = [
            ["Format", "SQLite format 3"],
            ["Page size", "\(effectivePageSize) bytes"],
            ["File change counter", "\(fileChangeCounter)"],
            ["Schema format", "\(schemaFormat)"],
            ["Text encoding", textEncoding],
            ["User version", "\(userVersion)"]
        ]
        if version > 0 {
            rows.append(["SQLite version", "\(version)"])
        }

        let tables = SQLiteDataReader.readDatabase(at: request.identity.url)
        var blocks: [PreviewBlock] = []

        if !tables.isEmpty {
            for table in tables {
                let rowCountStr = table.rows.count == table.totalCount ? "\(table.rows.count)" : "\(table.rows.count) of \(table.totalCount)"
                let tableTitle = "Table: \(table.name) (\(rowCountStr) \(table.totalCount == 1 ? "row" : "rows"))"
                blocks.append(.table(.init(
                    title: tableTitle,
                    columns: table.columns,
                    rows: table.rows
                )))
            }
        } else {
            blocks.append(.table(.init(
                title: "Database Header (No tables)",
                columns: ["Field", "Value"],
                rows: rows
            )))
        }

        var extraMetadata = [
            MetadataItem("Tables", "\(tables.count)"),
            MetadataItem("Page size", "\(effectivePageSize) bytes"),
            MetadataItem("Encoding", textEncoding)
        ]
        if let firstTable = tables.first {
            extraMetadata.insert(MetadataItem("Primary table", firstTable.name), at: 1)
        }

        return PreviewDocument(
            title: request.identity.filename,
            subtitle: "SQLite metadata",
            blocks: blocks,
            metadata: ProviderSupport.metadata(request: request, provider: descriptor, extra: extraMetadata),
            capabilities: descriptor.capabilities
        )
    }
}

private enum SQLiteDataReader {
    struct TableData: Sendable {
        let name: String
        let type: String
        let columns: [String]
        let rows: [[String]]
        let totalCount: Int
    }

    static func readDatabase(at url: URL, maxTables: Int = 10, maxRowsPerTable: Int = 100) -> [TableData] {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return []
        }
        defer { sqlite3_close(db) }

        let masterSQL = "SELECT name, type FROM sqlite_master WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%' ORDER BY name;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, masterSQL, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }

        var tableList: [(name: String, type: String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let nameC = sqlite3_column_text(stmt, 0),
               let typeC = sqlite3_column_text(stmt, 1) {
                tableList.append((String(cString: nameC), String(cString: typeC)))
            }
        }
        sqlite3_finalize(stmt)

        var results: [TableData] = []
        for (tableName, tableType) in tableList.prefix(maxTables) {
            let escapedName = tableName.replacingOccurrences(of: "\"", with: "\"\"")

            var totalCount = 0
            var countStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM \"\(escapedName)\";", -1, &countStmt, nil) == SQLITE_OK {
                if sqlite3_step(countStmt) == SQLITE_ROW {
                    totalCount = Int(sqlite3_column_int64(countStmt, 0))
                }
                sqlite3_finalize(countStmt)
            }

            let querySQL = "SELECT * FROM \"\(escapedName)\" LIMIT \(maxRowsPerTable);"
            var queryStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, querySQL, -1, &queryStmt, nil) == SQLITE_OK else {
                continue
            }

            let columnCount = sqlite3_column_count(queryStmt)
            var columnNames: [String] = []
            for col in 0..<columnCount {
                if let colNameC = sqlite3_column_name(queryStmt, col) {
                    columnNames.append(String(cString: colNameC))
                } else {
                    columnNames.append("col_\(col)")
                }
            }

            var rows: [[String]] = []
            while sqlite3_step(queryStmt) == SQLITE_ROW {
                var row: [String] = []
                for col in 0..<columnCount {
                    let colType = sqlite3_column_type(queryStmt, col)
                    switch colType {
                    case SQLITE_INTEGER:
                        row.append("\(sqlite3_column_int64(queryStmt, col))")
                    case SQLITE_FLOAT:
                        row.append("\(sqlite3_column_double(queryStmt, col))")
                    case SQLITE_TEXT:
                        if let textC = sqlite3_column_text(queryStmt, col) {
                            row.append(String(cString: textC))
                        } else {
                            row.append("")
                        }
                    case SQLITE_BLOB:
                        let bytes = sqlite3_column_bytes(queryStmt, col)
                        row.append("<blob \(bytes) B>")
                    case SQLITE_NULL:
                        row.append("NULL")
                    default:
                        if let textC = sqlite3_column_text(queryStmt, col) {
                            row.append(String(cString: textC))
                        } else {
                            row.append("")
                        }
                    }
                }
                rows.append(row)
            }
            sqlite3_finalize(queryStmt)

            results.append(TableData(
                name: tableName,
                type: tableType,
                columns: columnNames,
                rows: rows,
                totalCount: max(totalCount, rows.count)
            ))
        }

        return results
    }
}

public enum BuiltInProviders {
    public static func registerAll(into registry: ProviderRegistry) async throws {
        try await registry.register(ArchiveProvider())
        try await registry.register(SQLiteMetadataProvider())
        try await registry.register(JSONProvider())
        try await registry.register(YAMLProvider())
        try await registry.register(TOMLProvider())
        try await registry.register(XMLProvider())
        try await registry.register(CSVProvider())
        try await registry.register(MarkdownProvider())
        try await registry.register(LogProvider())
        try await registry.register(SourceCodeProvider())
        try await registry.register(TextProvider())
        try await registry.register(BinaryMetadataProvider())
    }

    public static func makeRuntime() async -> PreviewRuntime {
        let runtime = PreviewRuntime()
        try? await registerAll(into: runtime.registry)
        return runtime
    }
}

private struct ArchiveEntry {
    let path: String
    let compressedSize: UInt64?
    let uncompressedSize: UInt64?
    let kind: String
    let isUnsafe: Bool
    let modifiedAt: String?

    init(
        path: String,
        compressedSize: UInt64?,
        uncompressedSize: UInt64?,
        kind: String,
        isUnsafe: Bool,
        modifiedAt: String? = nil
    ) {
        self.path = path
        self.compressedSize = compressedSize
        self.uncompressedSize = uncompressedSize
        self.kind = kind
        self.isUnsafe = isUnsafe
        self.modifiedAt = modifiedAt
    }
}

private struct ArchiveInspection {
    let format: String
    let entries: [ArchiveEntry]
    let warnings: [PreviewWarning]
    let metadata: [MetadataItem]
    /// When set, the archive decompresses to a single text payload (e.g. `.txt.gz`)
    /// that should be shown directly rather than as a file tree.
    var textPayload: (content: String, language: String)?
    let explicitUncompressedSize: UInt64?

    init(
        format: String,
        entries: [ArchiveEntry],
        warnings: [PreviewWarning],
        metadata: [MetadataItem],
        textPayload: (content: String, language: String)? = nil,
        explicitUncompressedSize: UInt64? = nil
    ) {
        self.format = format
        self.entries = entries
        self.warnings = warnings
        self.metadata = metadata
        self.textPayload = textPayload
        self.explicitUncompressedSize = explicitUncompressedSize
    }

    var totalUncompressedSize: UInt64? {
        if let explicit = explicitUncompressedSize {
            return explicit
        }
        let uncompressedEntries = entries.compactMap(\.uncompressedSize)
        guard !uncompressedEntries.isEmpty else { return nil }
        return uncompressedEntries.reduce(0, +)
    }
}

private enum ArchiveInspector {
    static func inspect(request: PreviewRequest, descriptor: ProviderDescriptor) async throws -> PreviewDocument {
        let signatures = ProviderSupport.signatures(request)
        let ext = ProviderSupport.fileExtension(request)
        let inspection: ArchiveInspection
        if signatures.contains("zip") || ["zip", "jar", "war", "apk", "aar"].contains(ext) {
            inspection = try await inspectZip(request: request)
        } else if signatures.contains("tar") || ext == "tar" {
            inspection = try await inspectTar(request: request)
        } else if signatures.contains("gzip") || ["gz", "gzip", "tgz"].contains(ext) || request.identity.filename.lowercased().hasSuffix(".tar.gz") {
            inspection = try await inspectGzip(request: request)
        } else if signatures.contains("7z") || ext == "7z" {
            inspection = try await inspect7z(request: request)
        } else {
            throw PreviewError(.unsupported, "PreviewX could not identify a supported archive format.")
        }

        // A gzip'd single text file (e.g. sample.txt.gz) decompresses to text,
        // not a file tree, so render the inflated content directly.
        if let payload = inspection.textPayload {
            return PreviewDocument(
                title: request.identity.filename,
                subtitle: "\(inspection.format) (decompressed)",
                blocks: [.code(.init(content: payload.content, language: payload.language))],
                metadata: inspection.metadata,
                capabilities: descriptor.capabilities,
                warnings: inspection.warnings
            )
        }

        let unsafeCount = inspection.entries.filter(\.isUnsafe).count
        let tree = ArchiveTree.build(entries: inspection.entries)
        var warnings = inspection.warnings
        if unsafeCount > 0 {
            warnings.append(.init(kind: .security, message: "\(unsafeCount) archive entr\(unsafeCount == 1 ? "y" : "ies") use unsafe paths and would be blocked from extraction."))
        }
        var blocks: [PreviewBlock] = []

        let treeTitle = makeArchiveTreeTitle(request: request, inspection: inspection)

        if !tree.isEmpty {
            blocks.append(.tree(.init(title: treeTitle, roots: tree, columns: ["修改时间", "压缩前", "压缩后", "压缩率"])))
        } else {
            blocks.append(.error(.init(
                title: "\(inspection.format) Archive",
                message: inspection.warnings.first?.message ?? "No archive entries could be listed within the current inspection budget.",
                recoverySuggestion: "Container metadata is verified and displayed above."
            )))
        }

        var metadata = inspection.metadata
        if let totalUncompressed = inspection.totalUncompressedSize, totalUncompressed > 0 {
            metadata.append(MetadataItem("Uncompressed", ByteFormatHelper.format(totalUncompressed)))
            if request.identity.size > 0 {
                let ratio = (Double(request.identity.size) / Double(totalUncompressed)) * 100.0
                let saved = max(0, 100.0 - ratio)
                let ratioFormatted = String(format: "%.1f%% (节省 %.1f%%)", ratio, saved)
                metadata.append(MetadataItem("Compression ratio", ratioFormatted))
            }
        }

        return PreviewDocument(
            title: request.identity.filename,
            subtitle: "\(inspection.format) archive",
            blocks: blocks,
            metadata: metadata,
            capabilities: descriptor.capabilities,
            warnings: warnings
        )
    }

    private static func makeArchiveTreeTitle(request: PreviewRequest, inspection: ArchiveInspection) -> String {
        return "Archive Contents"
    }

    private static func inspect7z(request: PreviewRequest) async throws -> ArchiveInspection {
        let remaining = await request.resourceTracker.remainingBytes()
        let readable = min(request.identity.size, min(request.policy.budget.maxBytesRead, remaining))
        let headerData = try await FileAccess.read(
            request.identity.url,
            length: Int(min(32, readable)),
            budget: request.policy.budget,
            resourceTracker: request.resourceTracker
        )
        guard headerData.starts(with: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) else {
            throw PreviewError(.malformed, "Invalid 7-Zip archive signature.")
        }
        let major = headerData.count > 6 ? headerData[6] : 0
        let minor = headerData.count > 7 ? headerData[7] : 0
        let nextHeaderSize = headerData.count >= 28 ? ArchiveBytes.uint64LE(headerData, at: 20) : 0

        var metadata: [MetadataItem] = [
            MetadataItem("Format", "7-Zip Archive (7z)"),
            MetadataItem("Version", "v\(major).\(minor)"),
            MetadataItem("Archive size", ByteFormatHelper.format(request.identity.size))
        ]
        if nextHeaderSize > 0 {
            metadata.append(MetadataItem("Header size", ByteFormatHelper.format(nextHeaderSize)))
        }

        let entries: [ArchiveEntry] = [
            ArchiveEntry(
                path: "\(request.identity.filename)",
                compressedSize: request.identity.size,
                uncompressedSize: nil,
                kind: "7z Archive (v\(major).\(minor))",
                isUnsafe: false
            )
        ]

        return ArchiveInspection(
            format: "7Z",
            entries: entries,
            warnings: [],
            metadata: metadata
        )
    }

    private static func inspectZip(request: PreviewRequest) async throws -> ArchiveInspection {
        let remaining = await request.resourceTracker.remainingBytes()
        let maxTail = min(request.identity.size, min(remaining, 66_000))
        let tailOffset = request.identity.size - maxTail
        let tail = try await FileAccess.read(
            request.identity.url,
            offset: tailOffset,
            length: Int(maxTail),
            budget: request.policy.budget,
            resourceTracker: request.resourceTracker
        )
        guard let eocdOffset = ArchiveBytes.lastIndex(of: [0x50, 0x4B, 0x05, 0x06], in: tail), eocdOffset + 22 <= tail.count else {
            throw PreviewError(.malformed, "ZIP end-of-central-directory record was not found within the bounded read.")
        }
        let entryCount = Int(ArchiveBytes.uint16LE(tail, at: eocdOffset + 10))
        let centralSize = UInt64(ArchiveBytes.uint32LE(tail, at: eocdOffset + 12))
        let centralOffset = UInt64(ArchiveBytes.uint32LE(tail, at: eocdOffset + 16))
        var warnings: [PreviewWarning] = []
        if entryCount == 65_535 || centralSize == UInt64(UInt32.max) || centralOffset == UInt64(UInt32.max) {
            warnings.append(.init(kind: .unsupportedFeature, message: "ZIP64 metadata is only partially supported; entries may be incomplete."))
        }
        guard centralSize <= request.policy.budget.maxBytesRead else {
            throw PreviewError(.tooLarge, "The ZIP central directory exceeds the archive inspection budget.")
        }
        guard centralOffset <= request.identity.size, centralSize <= request.identity.size - centralOffset else {
            throw PreviewError(.malformed, "ZIP central-directory bounds are invalid.")
        }
        let directory = try await FileAccess.read(
            request.identity.url,
            offset: centralOffset,
            length: Int(centralSize),
            budget: request.policy.budget,
            resourceTracker: request.resourceTracker
        )
        var manifestInfo: (localOffset: UInt64, method: UInt16, compSize: UInt64, uncompSize: UInt64)?
        var entries: [ArchiveEntry] = []
        var cursor = 0
        while cursor + 46 <= directory.count && entries.count < Int(request.policy.budget.maxArchiveEntries) {
            guard ArchiveBytes.uint32LE(directory, at: cursor) == 0x0201_4B50 else {
                warnings.append(.init(kind: .malformed, message: "ZIP central directory contains an invalid entry header."))
                break
            }
            let compressionMethod = ArchiveBytes.uint16LE(directory, at: cursor + 10)
            let modTime = ArchiveBytes.uint16LE(directory, at: cursor + 12)
            let modDate = ArchiveBytes.uint16LE(directory, at: cursor + 14)
            let modifiedAt = ArchiveBytes.dosDateTime(time: modTime, date: modDate)
            let compressed = UInt64(ArchiveBytes.uint32LE(directory, at: cursor + 20))
            let uncompressed = UInt64(ArchiveBytes.uint32LE(directory, at: cursor + 24))
            let nameLength = Int(ArchiveBytes.uint16LE(directory, at: cursor + 28))
            let extraLength = Int(ArchiveBytes.uint16LE(directory, at: cursor + 30))
            let commentLength = Int(ArchiveBytes.uint16LE(directory, at: cursor + 32))
            let localHeaderOffset = UInt64(ArchiveBytes.uint32LE(directory, at: cursor + 42))
            let fullLength = 46 + nameLength + extraLength + commentLength
            guard cursor + fullLength <= directory.count else {
                warnings.append(.init(kind: .malformed, message: "ZIP entry name bounds are invalid."))
                break
            }
            let nameData = directory.subdata(in: (cursor + 46)..<(cursor + 46 + nameLength))
            let name = String(decoding: nameData, as: UTF8.self)
            let unsafe = ArchivePath.isUnsafe(name)
            entries.append(ArchiveEntry(
                path: name.isEmpty ? "(unnamed entry)" : name,
                compressedSize: compressed,
                uncompressedSize: uncompressed,
                kind: name.hasSuffix("/") ? "Directory" : "File",
                isUnsafe: unsafe,
                modifiedAt: modifiedAt
            ))
            if name.uppercased() == "META-INF/MANIFEST.MF" && uncompressed < 16 * 1024 {
                manifestInfo = (localOffset: localHeaderOffset, method: compressionMethod, compSize: compressed, uncompSize: uncompressed)
            }
            if compressed > 0, uncompressed / compressed > 1_000 {
                warnings.append(.init(kind: .security, message: "Archive contains an entry with a compression ratio above 1000:1."))
            }
            cursor += fullLength
        }
        if entryCount > entries.count || entries.count >= Int(request.policy.budget.maxArchiveEntries) {
            warnings.append(.init(kind: .truncated, message: "Archive entries were limited by the configured entry budget."))
        }

        var extraMetadata: [MetadataItem] = []
        if let info = manifestInfo, info.localOffset + 30 <= request.identity.size {
            if let localHeader = try? await FileAccess.read(
                request.identity.url,
                offset: info.localOffset,
                length: Int(min(30 + 1024, request.identity.size - info.localOffset)),
                budget: request.policy.budget,
                resourceTracker: request.resourceTracker
            ), localHeader.count >= 30, ArchiveBytes.uint32LE(localHeader, at: 0) == 0x0403_4B50 {
                let fnLen = Int(ArchiveBytes.uint16LE(localHeader, at: 26))
                let extraLen = Int(ArchiveBytes.uint16LE(localHeader, at: 28))
                let dataStart = 30 + fnLen + extraLen
                let dataOffset = info.localOffset + UInt64(dataStart)
                if dataOffset + info.compSize <= request.identity.size {
                    if let rawData = try? await FileAccess.read(
                        request.identity.url,
                        offset: dataOffset,
                        length: Int(info.compSize),
                        budget: request.policy.budget,
                        resourceTracker: request.resourceTracker
                    ) {
                        let manifestText: String?
                        if info.method == 0 {
                            manifestText = String(data: rawData, encoding: .utf8)
                        } else if info.method == 8 {
                            manifestText = (try? RawDeflateDecoder.inflate(rawData, maximumOutputBytes: Int(info.uncompSize))).flatMap { String(data: $0, encoding: .utf8) }
                        } else {
                            manifestText = nil
                        }
                        if let text = manifestText {
                            extraMetadata.append(contentsOf: parseManifest(text))
                        }
                    }
                }
            }
        }

        let ext = ProviderSupport.fileExtension(request)
        var format = "ZIP"
        if ext == "jar" || entries.contains(where: { $0.path.uppercased() == "META-INF/MANIFEST.MF" }) {
            format = "JAR"
        } else if ext == "war" {
            format = "WAR"
        } else if ext == "apk" {
            format = "APK"
        } else if ext == "aar" {
            format = "AAR"
        }

        var metadataItems = [
            MetadataItem("Central directory", ByteFormatHelper.format(centralSize)),
            MetadataItem("Declared entries", "\(entryCount)")
        ]
        metadataItems.append(contentsOf: extraMetadata)

        return ArchiveInspection(
            format: format,
            entries: entries,
            warnings: deduplicated(warnings),
            metadata: metadataItems
        )
    }

    private static func parseManifest(_ text: String) -> [MetadataItem] {
        var items: [MetadataItem] = []
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let val = parts[1].trimmingCharacters(in: .whitespaces)
                if ["Main-Class", "Created-By", "Build-Jdk", "Implementation-Version", "Bundle-Version", "Manifest-Version"].contains(key) {
                    items.append(MetadataItem(key, val))
                }
            }
        }
        return items
    }

    private static func inspectTar(request: PreviewRequest) async throws -> ArchiveInspection {
        let remaining = await request.resourceTracker.remainingBytes()
        let readable = min(request.identity.size, min(request.policy.budget.maxBytesRead, remaining))
        let data = try await FileAccess.read(
            request.identity.url,
            length: Int(readable),
            budget: request.policy.budget,
            resourceTracker: request.resourceTracker
        )
        return inspectTarData(
            data,
            sourceSize: request.identity.size,
            maximumEntries: request.policy.budget.maxArchiveEntries
        )
    }

    private static func inspectTarData(
        _ data: Data,
        sourceSize: UInt64,
        maximumEntries: UInt64,
        compressionRatio: Double? = nil
    ) -> ArchiveInspection {
        var entries: [ArchiveEntry] = []
        var warnings: [PreviewWarning] = []
        var offset = 0
        while offset + 512 <= data.count && entries.count < Int(maximumEntries) {
            let header = data.subdata(in: offset..<(offset + 512))
            if header.allSatisfy({ $0 == 0 }) { break }
            let name = ArchiveBytes.cString(header, range: 0..<100)
            let prefix = ArchiveBytes.cString(header, range: 345..<500)
            let fullName = [prefix, name].filter { !$0.isEmpty }.joined(separator: "/")
            let rawSize = ArchiveBytes.cString(header, range: 124..<136)
            guard let size = ArchiveBytes.octal(rawSize) else {
                warnings.append(.init(kind: .malformed, message: "TAR entry at offset \(offset) has an invalid size field."))
                break
            }
            let typeFlag = header[156]
            let kind: String
            switch typeFlag {
            case 53: kind = "Directory"
            case 50: kind = "Symlink"
            case 49, 0: kind = "File"
            default: kind = "Other"
            }
            let rawMtime = ArchiveBytes.cString(header, range: 136..<148)
            let mtimeSec = ArchiveBytes.octal(rawMtime) ?? 0
            let modifiedAt = ArchiveBytes.formatUnixTimestamp(mtimeSec)
            let compressedSize: UInt64?
            if let ratio = compressionRatio, size > 0 {
                compressedSize = max(1, UInt64(round(Double(size) * ratio)))
            } else {
                compressedSize = nil
            }
            entries.append(ArchiveEntry(
                path: fullName.isEmpty ? "(unnamed entry)" : fullName,
                compressedSize: compressedSize,
                uncompressedSize: size,
                kind: kind,
                isUnsafe: ArchivePath.isUnsafe(fullName) || kind == "Symlink",
                modifiedAt: modifiedAt
            ))
            let paddedSize = ((size + 511) / 512) * 512
            guard paddedSize <= UInt64(Int.max), offset <= Int.max - 512 - Int(paddedSize) else {
                warnings.append(.init(kind: .malformed, message: "TAR entry size overflows safe preview bounds."))
                break
            }
            offset += 512 + Int(paddedSize)
        }
        if offset < Int(sourceSize), UInt64(data.count) < sourceSize {
            warnings.append(.init(kind: .truncated, message: "Only the archive prefix was inspected within the read budget."))
        }
        let validEntries = entries.filter { entry in
            let p = entry.path
            return !p.hasPrefix("PaxHeader") && !p.contains("/PaxHeader/") && !p.hasPrefix("._") && !p.contains("/._")
        }
        let finalEntries = validEntries.isEmpty ? entries : validEntries
        let metadata: [MetadataItem] = [
            MetadataItem("Format", "TAR Archive"),
            MetadataItem("Entries", "\(finalEntries.count) items"),
            MetadataItem("Archive size", ByteFormatHelper.format(sourceSize))
        ]
        return ArchiveInspection(format: "TAR", entries: finalEntries, warnings: deduplicated(warnings), metadata: metadata)
    }

    private static func inspectGzip(request: PreviewRequest) async throws -> ArchiveInspection {
        let remaining = await request.resourceTracker.remainingBytes()
        if request.identity.filename.lowercased().hasSuffix(".tar.gz") || ProviderSupport.fileExtension(request) == "tgz" {
            guard request.identity.size <= remaining else {
                return ArchiveInspection(
                    format: "TAR.GZ",
                    entries: [],
                    warnings: [.init(kind: .truncated, message: "The compressed TAR exceeds the remaining read budget, so only GZIP metadata can be shown.")],
                    metadata: [MetadataItem("Compression", "GZIP")]
                )
            }
            let compressed = try await FileAccess.read(
                request.identity.url,
                length: Int(request.identity.size),
                budget: request.policy.budget,
                resourceTracker: request.resourceTracker
            )
            let outputLimit = Int(min(request.policy.budget.maxMemoryBytes, UInt64(Int.max)))
            let tarData = try GzipDecoder.inflate(compressed, maximumOutputBytes: outputLimit)
            let ratio = tarData.isEmpty ? 1.0 : Double(request.identity.size) / Double(tarData.count)
            var inspection = inspectTarData(
                tarData,
                sourceSize: UInt64(tarData.count),
                maximumEntries: request.policy.budget.maxArchiveEntries,
                compressionRatio: ratio
            )
            inspection = ArchiveInspection(
                format: "TAR.GZ",
                entries: inspection.entries,
                warnings: inspection.warnings,
                metadata: [
                    MetadataItem("Compression", "GZIP"),
                    MetadataItem("Inflated bytes", ByteFormatHelper.format(UInt64(tarData.count)))
                ],
                explicitUncompressedSize: UInt64(tarData.count)
            )
            return inspection
        }
        let head = try await FileAccess.read(
            request.identity.url,
            length: Int(min(64, remaining)),
            budget: request.policy.budget,
            resourceTracker: request.resourceTracker
        )
        guard head.starts(with: [0x1F, 0x8B]) else {
            throw PreviewError(.malformed, "The file does not have a valid GZIP header.")
        }
        var metadata = [MetadataItem("Compression", "GZIP")]
        if request.identity.size >= 4 {
            let trailer = try await FileAccess.read(
                request.identity.url,
                offset: request.identity.size - 4,
                length: 4,
                budget: request.policy.budget,
                resourceTracker: request.resourceTracker
            )
            metadata.append(MetadataItem("Original size (mod 4 GiB)", ByteFormatHelper.format(UInt64(ArchiveBytes.uint32LE(trailer, at: 0)))))
        }

        // A single gzip'd text file (sample.txt.gz / sample.txt.gzip) should be
        // decompressed and shown as text rather than as opaque metadata.
        let filename = request.identity.filename.lowercased()
        let looksLikeText = filename.hasSuffix(".txt.gz")
            || filename.hasSuffix(".txt.gzip")
            || filename.hasSuffix(".log.gz")
            || filename.hasSuffix(".json.gz")
        if looksLikeText, request.identity.size <= remaining {
            let compressed = try await FileAccess.read(
                request.identity.url,
                length: Int(request.identity.size),
                budget: request.policy.budget,
                resourceTracker: request.resourceTracker
            )
            let outputLimit = Int(min(request.policy.budget.maxMemoryBytes, UInt64(Int.max)))
            if let inflated = try? GzipDecoder.inflate(compressed, maximumOutputBytes: outputLimit) {
                let text = String(decoding: inflated, as: UTF8.self)
                let language = filename.hasSuffix(".json.gz") ? "json" : "plaintext"
                metadata.append(MetadataItem("Inflated bytes", ByteFormatHelper.format(UInt64(inflated.count))))
                return ArchiveInspection(
                    format: "GZIP",
                    entries: [],
                    warnings: [],
                    metadata: metadata,
                    textPayload: (text, language)
                )
            }
        }

        return ArchiveInspection(
            format: "GZIP",
            entries: [],
            warnings: [.init(kind: .unsupportedFeature, message: "GZIP streams are inspected as metadata only; nested content is not implicitly decompressed.")],
            metadata: metadata
        )
    }

    private static func deduplicated(_ warnings: [PreviewWarning]) -> [PreviewWarning] {
        var messages = Set<String>()
        return warnings.filter { messages.insert($0.message).inserted }
    }
}

private enum GzipDecoder {
    static func inflate(_ input: Data, maximumOutputBytes: Int) throws -> Data {
        guard !input.isEmpty else {
            throw PreviewError(.malformed, "The GZIP stream is empty.")
        }
        guard maximumOutputBytes > 0 else {
            throw PreviewError(.memoryLimit, "No memory is available for GZIP inspection.")
        }

        return try input.withUnsafeBytes { rawInput in
            guard let inputBase = rawInput.bindMemory(to: Bytef.self).baseAddress else {
                throw PreviewError(.malformed, "The GZIP stream has no readable bytes.")
            }
            var stream = z_stream()
            stream.next_in = UnsafeMutablePointer(mutating: inputBase)
            stream.avail_in = uInt(input.count)
            let initialization = inflateInit2_(&stream, 16 + MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            guard initialization == Z_OK else {
                throw PreviewError(.malformed, "Unable to initialize the GZIP decoder.")
            }
            defer { inflateEnd(&stream) }

            var output = Data()
            var status: Int32 = Z_OK
            repeat {
                guard output.count < maximumOutputBytes else {
                    throw PreviewError(.memoryLimit, "Inflated archive data exceeds the memory budget.")
                }
                let capacity = min(64 * 1_024, maximumOutputBytes - output.count)
                var chunk = [UInt8](repeating: 0, count: capacity)
                let produced: Int = try chunk.withUnsafeMutableBytes { rawOutput in
                    stream.next_out = rawOutput.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(capacity)
                    status = zlib.inflate(&stream, Z_NO_FLUSH)
                    guard status == Z_OK || status == Z_STREAM_END else {
                        throw PreviewError(.malformed, "GZIP decoding failed with zlib status \(status).")
                    }
                    return capacity - Int(stream.avail_out)
                }
                output.append(contentsOf: chunk.prefix(produced))
            } while status != Z_STREAM_END
            return output
        }
    }
}

private enum RawDeflateDecoder {
    static func inflate(_ input: Data, maximumOutputBytes: Int) throws -> Data {
        guard !input.isEmpty else { return Data() }
        guard maximumOutputBytes > 0 else {
            throw PreviewError(.memoryLimit, "No memory is available for deflate inspection.")
        }

        return try input.withUnsafeBytes { rawInput in
            guard let inputBase = rawInput.bindMemory(to: Bytef.self).baseAddress else {
                throw PreviewError(.malformed, "The stream has no readable bytes.")
            }
            var stream = z_stream()
            stream.next_in = UnsafeMutablePointer(mutating: inputBase)
            stream.avail_in = uInt(input.count)
            // -MAX_WBITS instructs zlib to decompress raw DEFLATE without gzip or zlib header
            let initialization = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            guard initialization == Z_OK else {
                throw PreviewError(.malformed, "Unable to initialize the raw DEFLATE decoder.")
            }
            defer { inflateEnd(&stream) }

            var output = Data()
            var status: Int32 = Z_OK
            repeat {
                guard output.count < maximumOutputBytes else {
                    throw PreviewError(.memoryLimit, "Inflated data exceeds the memory budget.")
                }
                let capacity = min(64 * 1_024, maximumOutputBytes - output.count)
                var chunk = [UInt8](repeating: 0, count: capacity)
                let produced: Int = try chunk.withUnsafeMutableBytes { rawOutput in
                    stream.next_out = rawOutput.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(capacity)
                    status = zlib.inflate(&stream, Z_NO_FLUSH)
                    guard status == Z_OK || status == Z_STREAM_END else {
                        throw PreviewError(.malformed, "Deflate decoding failed with zlib status \(status).")
                    }
                    return capacity - Int(stream.avail_out)
                }
                output.append(contentsOf: chunk.prefix(produced))
            } while status != Z_STREAM_END
            return output
        }
    }
}

private enum ArchivePath {
    static func isUnsafe(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        if path.contains("\0") || path.hasPrefix("/") || path.hasPrefix("\\") || path.contains(":\\") {
            return true
        }
        return path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }
}

private enum ArchiveTree {
    private final class Node {
        let label: String
        var isUnsafe = false
        var isFile = false
        var uncompressedSize: UInt64 = 0
        var compressedSize: UInt64 = 0
        var hasExplicitSize = false
        var modifiedAt: String?
        var value: String?
        var detailColumns: [String]?
        var children: [String: Node] = [:]

        init(label: String) { self.label = label }
    }

    static func build(entries: [ArchiveEntry]) -> [TreeNode] {
        let root = Node(label: "root")
        for entry in entries {
            var node = root
            let components = entry.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard !components.isEmpty else { continue }

            for (index, component) in components.enumerated() {
                let isLeaf = (index == components.count - 1)
                let child: Node
                if let existing = node.children[component] {
                    child = existing
                } else {
                    child = Node(label: component)
                    node.children[component] = child
                }
                if isLeaf {
                    child.isUnsafe = entry.isUnsafe
                    child.modifiedAt = entry.modifiedAt
                    let isDirectoryEntry = (entry.kind == "Directory" || entry.path.hasSuffix("/"))
                    child.isFile = !isDirectoryEntry

                    if let uncompressed = entry.uncompressedSize {
                        child.uncompressedSize = uncompressed
                        child.hasExplicitSize = true
                    }
                    if let compressed = entry.compressedSize {
                        child.compressedSize = compressed
                    } else if let uncompressed = entry.uncompressedSize {
                        child.compressedSize = uncompressed
                    }
                }
                node = child
            }
        }

        for child in root.children.values {
            rollupAndFormat(child)
        }

        return root.children.values
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
            .map(freeze)
    }

    @discardableResult
    private static func rollupAndFormat(_ node: Node) -> (uncompressed: UInt64, compressed: UInt64, hasSize: Bool) {
        if node.children.isEmpty {
            let hasSize = node.hasExplicitSize || node.uncompressedSize > 0 || node.isFile
            let uStr = hasSize ? ByteFormatHelper.format(node.uncompressedSize) : "-"
            let cStr: String
            if node.compressedSize > 0 && node.compressedSize < node.uncompressedSize {
                cStr = ByteFormatHelper.format(node.compressedSize)
            } else if hasSize && node.uncompressedSize > 0 {
                cStr = uStr
            } else {
                cStr = "-"
            }
            let modStr = node.modifiedAt ?? "-"
            let ratioStr: String
            if hasSize && node.uncompressedSize > 0 && node.compressedSize > 0 {
                let ratio = (Double(node.compressedSize) / Double(node.uncompressedSize)) * 100.0
                let saved = max(0.0, 100.0 - ratio)
                if saved < 1.0 && saved > 0.0 {
                    ratioStr = "<1%"
                } else {
                    ratioStr = String(format: "%.0f%%", saved)
                }
            } else {
                ratioStr = "-"
            }
            node.detailColumns = [modStr, uStr, cStr, ratioStr]
            node.value = (node.compressedSize > 0 && node.compressedSize < node.uncompressedSize) ? "原 \(uStr) → 压缩后 \(cStr) (\(ratioStr))" : (hasSize ? uStr : nil)
            return (node.uncompressedSize, node.compressedSize, hasSize)
        } else {
            var totalUncompressed: UInt64 = 0
            var totalCompressed: UInt64 = 0
            var anyChildHasSize = false
            var anyChildUnsafe = false

            for child in node.children.values {
                let (cUncomp, cComp, cHasSize) = rollupAndFormat(child)
                totalUncompressed += cUncomp
                totalCompressed += cComp
                if cHasSize { anyChildHasSize = true }
                if child.isUnsafe { anyChildUnsafe = true }
                if let childMod = child.modifiedAt, childMod != "-" {
                    if let cur = node.modifiedAt {
                        node.modifiedAt = max(cur, childMod)
                    } else {
                        node.modifiedAt = childMod
                    }
                }
            }

            node.uncompressedSize = totalUncompressed
            node.compressedSize = totalCompressed
            node.isUnsafe = node.isUnsafe || anyChildUnsafe
            node.hasExplicitSize = anyChildHasSize

            let uStr = anyChildHasSize ? ByteFormatHelper.format(totalUncompressed) : "-"
            let cStr: String
            if totalCompressed > 0 && totalCompressed < totalUncompressed {
                cStr = ByteFormatHelper.format(totalCompressed)
            } else if anyChildHasSize && totalUncompressed > 0 {
                cStr = uStr
            } else {
                cStr = "-"
            }
            let modStr = node.modifiedAt ?? "-"
            let ratioStr: String
            if anyChildHasSize && totalUncompressed > 0 && totalCompressed > 0 {
                let ratio = (Double(totalCompressed) / Double(totalUncompressed)) * 100.0
                let saved = max(0.0, 100.0 - ratio)
                if saved < 1.0 && saved > 0.0 {
                    ratioStr = "<1%"
                } else {
                    ratioStr = String(format: "%.0f%%", saved)
                }
            } else {
                ratioStr = "-"
            }
            node.detailColumns = [modStr, uStr, cStr, ratioStr]
            node.value = (totalCompressed > 0 && totalCompressed < totalUncompressed) ? "原 \(uStr) → 压缩后 \(cStr) (\(ratioStr))" : (anyChildHasSize ? uStr : nil)
            return (totalUncompressed, totalCompressed, anyChildHasSize)
        }
    }

    private static func freeze(_ node: Node) -> TreeNode {
        TreeNode(
            label: node.label,
            value: node.value,
            detailColumns: node.detailColumns,
            children: node.children.values.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }.map(freeze),
            isUnsafe: node.isUnsafe
        )
    }
}

private enum ArchiveBytes {
    static func uint16LE(_ data: Data, at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    static func uint32LE(_ data: Data, at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    static func uint64LE(_ data: Data, at offset: Int) -> UInt64 {
        guard offset >= 0, offset + 8 <= data.count else { return 0 }
        let low = UInt64(uint32LE(data, at: offset))
        let high = UInt64(uint32LE(data, at: offset + 4))
        return low | (high << 32)
    }

    static func uint16BE(_ data: Data, at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { return 0 }
        return (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }

    static func uint32BE(_ data: Data, at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        return (UInt32(data[offset]) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
    }

    static func cString(_ data: Data, range: Range<Int>) -> String {
        guard range.lowerBound >= 0, range.upperBound <= data.count else { return "" }
        let bytes = data[range].prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func octal(_ text: String) -> UInt64? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        guard !value.isEmpty else { return 0 }
        return UInt64(value, radix: 8)
    }

    static func lastIndex(of needle: [UInt8], in haystack: Data) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        for index in stride(from: haystack.count - needle.count, through: 0, by: -1) {
            if haystack[index..<(index + needle.count)].elementsEqual(needle) {
                return index
            }
        }
        return nil
    }

    static func dosDateTime(time: UInt16, date: UInt16) -> String {
        guard date > 0 else { return "-" }
        let minute = Int((time >> 5) & 0x3F)
        let hour = Int((time >> 11) & 0x1F)
        let day = Int(date & 0x1F)
        let month = Int((date >> 5) & 0x0F)
        let year = Int((date >> 9) & 0x7F) + 1980
        guard month >= 1, month <= 12, day >= 1, day <= 31 else { return "-" }
        return String(format: "%04d-%02d-%02d %02d:%02d", year, month, day, hour, minute)
    }

    static func formatUnixTimestamp(_ timestamp: UInt64) -> String {
        guard timestamp > 0, timestamp < 4_102_444_800 else { return "-" }
        var timeVal = time_t(timestamp)
        var tmStruct = tm()
        localtime_r(&timeVal, &tmStruct)
        var buffer = [CChar](repeating: 0, count: 32)
        strftime(&buffer, buffer.count, "%Y-%m-%d %H:%M", &tmStruct)
        return buffer.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return "-" }
            return String(cString: base)
        }
    }
}
