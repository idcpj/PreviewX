import Foundation

public enum PreviewDiagnosticPhase: String, Codable, Sendable {
    case classification
    case routing
    case rendering
}

public enum PreviewDiagnosticStatus: String, Codable, Sendable {
    case success
    case partial
    case unsupported
    case failed
}

public struct PreviewDiagnostic: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let requestID: UUID
    public let filename: String
    public let providerID: String?
    public let phase: PreviewDiagnosticPhase
    public let durationMs: UInt64
    public let bytesRead: UInt64
    public let status: PreviewDiagnosticStatus
    public let message: String?

    public init(
        requestID: UUID,
        filename: String,
        providerID: String?,
        phase: PreviewDiagnosticPhase,
        durationMs: UInt64,
        bytesRead: UInt64,
        status: PreviewDiagnosticStatus,
        message: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.requestID = requestID
        self.filename = filename
        self.providerID = providerID
        self.phase = phase
        self.durationMs = durationMs
        self.bytesRead = bytesRead
        self.status = status
        self.message = message
    }
}

public actor DiagnosticsStore {
    private var events: [PreviewDiagnostic] = []
    private let capacity: Int
    private let fileURL: URL?

    public init(capacity: Int = 250, fileURL: URL? = nil) {
        self.capacity = max(1, capacity)
        self.fileURL = fileURL
        if let fileURL,
           let data = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            events = (try? decoder.decode([PreviewDiagnostic].self, from: data)) ?? []
            if events.count > self.capacity {
                events = Array(events.suffix(self.capacity))
            }
        }
    }

    public func record(_ event: PreviewDiagnostic) {
        events.append(event)
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
        persist()
    }

    public func recentEvents() -> [PreviewDiagnostic] {
        events.sorted { $0.timestamp > $1.timestamp }
    }

    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(recentEvents())
    }

    private func persist() {
        guard let fileURL else { return }
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(events).write(to: fileURL, options: .atomic)
        } catch {
            // Diagnostics persistence is intentionally best-effort and cannot block previewing.
        }
    }
}

public actor PreviewRuntime {
    public let registry: ProviderRegistry
    public let diagnostics: DiagnosticsStore
    private let classifier: FileClassifier

    public init(
        registry: ProviderRegistry = ProviderRegistry(),
        diagnostics: DiagnosticsStore = DiagnosticsStore(),
        classifier: FileClassifier = FileClassifier()
    ) {
        self.registry = registry
        self.diagnostics = diagnostics
        self.classifier = classifier
    }

    public func preview(
        fileURL: URL,
        policy: PreviewPolicy = .default,
        timeout: TimeInterval? = nil
    ) async -> PreviewResult {
        let requestID = UUID()
        let started = Date()

        do {
            let identity = try FileAccess.identity(for: fileURL)
            let resourceTracker = PreviewResourceTracker(maxBytesRead: policy.budget.maxBytesRead)
            let classification = try await classifier.classify(
                identity: identity,
                budget: policy.budget,
                resourceTracker: resourceTracker
            )
            let deadline = Date().addingTimeInterval(timeout ?? Double(policy.budget.maxCPUTimeMs) / 1_000)
            let request = PreviewRequest(
                identity: identity,
                classification: classification,
                deadline: deadline,
                policy: policy,
                resourceTracker: resourceTracker
            )
            return await preview(request, requestID: requestID, started: started)
        } catch let error as PreviewError {
            let result = PreviewResult.failed(error)
            await record(
                requestID: requestID,
                filename: fileURL.lastPathComponent,
                providerID: nil,
                started: started,
                bytesRead: 0,
                result: result
            )
            return result
        } catch {
            let result = PreviewResult.failed(PreviewError(.unknown, error.localizedDescription))
            await record(
                requestID: requestID,
                filename: fileURL.lastPathComponent,
                providerID: nil,
                started: started,
                bytesRead: 0,
                result: result
            )
            return result
        }
    }

    public func preview(_ request: PreviewRequest) async -> PreviewResult {
        await preview(request, requestID: UUID(), started: Date())
    }

    private func preview(_ request: PreviewRequest, requestID: UUID, started: Date) async -> PreviewResult {
        guard !request.isExpired else {
            let result = PreviewResult.failed(PreviewError(.timeout, "Preview timed out before a provider was selected."))
            await record(requestID: requestID, filename: request.identity.filename, providerID: nil, started: started, bytesRead: 0, result: result)
            return result
        }

        let registered = await registry.providers()
        var candidates: [ProviderSelection] = []
        for provider in registered {
            if let enabled = request.policy.enabledProviderIDs, !enabled.contains(provider.descriptor.id) {
                continue
            }
            let match = await provider.canPreview(request)
            if match.confidence > 0 {
                candidates.append(ProviderSelection(provider: provider, match: match))
            }
        }

        guard let selected = candidates.sorted(by: { lhs, rhs in
            selectionComesBefore(lhs, rhs, preferredProviderID: request.policy.preferredProviderID)
        }).first else {
            let result = PreviewResult.unsupported("No enabled PreviewX provider supports this file.")
            await record(requestID: requestID, filename: request.identity.filename, providerID: nil, started: started, bytesRead: 0, result: result)
            return result
        }

        do {
            let document = try await makePreview(selected.provider, request: request)
            let result: PreviewResult = document.warnings.isEmpty
                ? .success(document)
                : .partial(document, warnings: document.warnings)
            await record(
                requestID: requestID,
                filename: request.identity.filename,
                providerID: selected.provider.descriptor.id,
                started: started,
                bytesRead: min(request.identity.size, request.policy.budget.maxBytesRead),
                result: result
            )
            return result
        } catch let error as PreviewError {
            let result = PreviewResult.failed(error)
            await record(
                requestID: requestID,
                filename: request.identity.filename,
                providerID: selected.provider.descriptor.id,
                started: started,
                bytesRead: 0,
                result: result
            )
            return result
        } catch is CancellationError {
            let result = PreviewResult.failed(PreviewError(.timeout, "Preview was cancelled."))
            await record(
                requestID: requestID,
                filename: request.identity.filename,
                providerID: selected.provider.descriptor.id,
                started: started,
                bytesRead: 0,
                result: result
            )
            return result
        } catch {
            let result = PreviewResult.failed(PreviewError(.unknown, error.localizedDescription))
            await record(
                requestID: requestID,
                filename: request.identity.filename,
                providerID: selected.provider.descriptor.id,
                started: started,
                bytesRead: 0,
                result: result
            )
            return result
        }
    }

    private func makePreview(_ provider: any PreviewProvider, request: PreviewRequest) async throws -> PreviewDocument {
        let remaining = request.deadline.timeIntervalSinceNow
        guard remaining > 0 else {
            throw PreviewError(.timeout, "Preview exceeded its time budget.")
        }

        return try await withThrowingTaskGroup(of: PreviewDocument.self) { group in
            group.addTask {
                try await provider.makePreview(request)
            }
            group.addTask {
                let nanoseconds = UInt64(min(remaining, 60) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                throw PreviewError(.timeout, "Preview exceeded its time budget.")
            }

            guard let first = try await group.next() else {
                throw PreviewError(.unknown, "Preview provider did not produce a result.")
            }
            group.cancelAll()
            return first
        }
    }

    private func selectionComesBefore(
        _ lhs: ProviderSelection,
        _ rhs: ProviderSelection,
        preferredProviderID: String?
    ) -> Bool {
        if let preferred = preferredProviderID, lhs.provider.descriptor.id == preferred || rhs.provider.descriptor.id == preferred {
            return lhs.provider.descriptor.id == preferred
        }
        if lhs.match.confidence != rhs.match.confidence {
            return lhs.match.confidence > rhs.match.confidence
        }
        if lhs.match.specificity != rhs.match.specificity {
            return lhs.match.specificity > rhs.match.specificity
        }
        if lhs.provider.descriptor.priority != rhs.provider.descriptor.priority {
            return lhs.provider.descriptor.priority > rhs.provider.descriptor.priority
        }
        if lhs.provider.descriptor.isBuiltIn != rhs.provider.descriptor.isBuiltIn {
            return lhs.provider.descriptor.isBuiltIn
        }
        let leftVersion = SemanticVersion(lhs.provider.descriptor.version)
        let rightVersion = SemanticVersion(rhs.provider.descriptor.version)
        if leftVersion != rightVersion {
            return leftVersion > rightVersion
        }
        return lhs.provider.descriptor.id < rhs.provider.descriptor.id
    }

    private func record(
        requestID: UUID,
        filename: String,
        providerID: String?,
        started: Date,
        bytesRead: UInt64,
        result: PreviewResult
    ) async {
        let duration = UInt64(max(0, Date().timeIntervalSince(started) * 1_000))
        let status: PreviewDiagnosticStatus
        let message: String?
        switch result {
        case .success:
            status = .success
            message = nil
        case let .partial(_, warnings):
            status = .partial
            message = warnings.map(\.message).joined(separator: " ")
        case let .unsupported(reason):
            status = .unsupported
            message = reason
        case let .failed(error):
            status = .failed
            message = error.message
        }
        await diagnostics.record(
            PreviewDiagnostic(
                requestID: requestID,
                filename: filename,
                providerID: providerID,
                phase: .rendering,
                durationMs: duration,
                bytesRead: bytesRead,
                status: status,
                message: message
            )
        )
    }
}

private struct SemanticVersion: Comparable, Equatable {
    let components: [Int]

    init(_ value: String) {
        components = value.split(separator: ".").map { Int($0) ?? 0 }
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}
