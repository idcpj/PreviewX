import AppKit
import Foundation
import PreviewXCore
import PreviewXProviders
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public final class PreviewWorkspaceModel: ObservableObject {
    @Published public private(set) var result: PreviewResult?
    @Published public private(set) var providerDescriptors: [ProviderDescriptor] = []
    @Published public private(set) var diagnostics: [PreviewDiagnostic] = []
    @Published public private(set) var currentURL: URL?
    @Published public private(set) var isLoading = false
    @Published public var settings = PreviewXSettings()
    @Published public var searchText = ""
    @Published public var requestedLine: Int?

    public let runtime: PreviewRuntime
    private let settingsStore: SettingsStore
    private var hasBootstrapped = false
    private var previewTask: Task<Void, Never>?

    public init(runtime: PreviewRuntime? = nil, settingsURL: URL? = nil) {
        let resolvedSettingsURL = settingsURL ?? PreviewXPaths.settingsURL()
        self.settingsStore = SettingsStore(fileURL: resolvedSettingsURL)
        self.runtime = runtime ?? PreviewRuntime(
            diagnostics: DiagnosticsStore(fileURL: PreviewXPaths.diagnosticsURL())
        )
    }

    deinit {
        previewTask?.cancel()
    }

    public func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        settings = await settingsStore.settings()
        applyAppearance()
        do {
            try await BuiltInProviders.registerAll(into: runtime.registry)
        } catch let error as PreviewError where error.reason != .providerUnavailable {
            result = .failed(error)
        } catch {
            result = .failed(PreviewError(.unknown, error.localizedDescription))
        }
        providerDescriptors = await runtime.registry.descriptors()
        await refreshDiagnostics()
    }

    public func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = settings.language.tr(.openFilePrompt)
        if panel.runModal() == .OK, let url = panel.url {
            preview(url: url)
        }
    }

    public func preview(url: URL) {
        previewTask?.cancel()
        previewTask = Task { [weak self, runtime] in
            guard let self else { return }
            await self.bootstrap()
            guard !Task.isCancelled else { return }
            self.beginPreview(url: url)
            let policy = self.effectivePolicy()
            let accessedSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if accessedSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let previewResult = await runtime.preview(fileURL: url, policy: policy)
            guard !Task.isCancelled else { return }
            self.result = previewResult
            self.isLoading = false
            await self.refreshDiagnostics()
        }
    }

    public func previewImmediately(url: URL) async {
        previewTask?.cancel()
        beginPreview(url: url)
        let accessedSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let previewResult = await runtime.preview(fileURL: url, policy: effectivePolicy())
        guard !Task.isCancelled else { return }
        result = previewResult
        isLoading = false
        await refreshDiagnostics()
    }

    public func setProviderEnabled(_ descriptor: ProviderDescriptor, enabled: Bool) {
        var state = settings.providerStates[descriptor.id] ?? ProviderState()
        state.isEnabled = enabled
        settings.providerStates[descriptor.id] = state
        persistSettings()
        if let currentURL {
            preview(url: currentURL)
        }
    }


    public func resetSettings() {
        settings = PreviewXSettings()
        applyAppearance()
        persistSettings()
        if let currentURL {
            preview(url: currentURL)
        }
    }

    public func refreshDiagnostics() async {
        diagnostics = await runtime.diagnostics.recentEvents()
    }

    public func saveSettings() {
        applyAppearance()
        persistSettings()
    }

    public func applyAppearance() {
        NSApp.appearance = settings.appearance.nsAppearance
    }

    public func handleDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = item as? URL
            }
            if let url {
                Task { @MainActor in self?.preview(url: url) }
            }
        }
        return true
    }

    private func effectivePolicy() -> PreviewPolicy {
        var policy = settings.policy
        let enabled = Set(providerDescriptors.compactMap { descriptor in
            let state = settings.providerStates[descriptor.id] ?? ProviderState()
            return state.isEnabled ? descriptor.id : nil
        })
        policy.enabledProviderIDs = enabled
        return policy
    }

    private func beginPreview(url: URL) {
        currentURL = url
        result = nil
        searchText = ""
        requestedLine = nil
        isLoading = true
    }

    private func persistSettings() {
        let value = settings
        Task {
            try? await settingsStore.update(value)
        }
    }

    private static func defaultSettingsURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return root.appendingPathComponent("PreviewX", isDirectory: true).appendingPathComponent("settings.json")
    }

    private static func defaultDiagnosticsURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return root.appendingPathComponent("PreviewX", isDirectory: true).appendingPathComponent("diagnostics.json")
    }
}

public struct PreviewWorkspaceView: View {
    @ObservedObject private var model: PreviewWorkspaceModel
    @State private var section: WorkspaceSection = .formats

    public init(model: PreviewWorkspaceModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                if let currentURL = model.currentURL {
                    Section(model.settings.language.tr(.currentFile)) {
                        NavigationLink(value: WorkspaceSection.preview) {
                            Label(currentURL.lastPathComponent, systemImage: "doc.text.magnifyingglass")
                        }
                    }
                }

                Section(model.settings.language.tr(.general)) {
                    NavigationLink(value: WorkspaceSection.formats) {
                        Label(model.settings.language.tr(.formatsAndRules), systemImage: "square.grid.2x2")
                    }
                    NavigationLink(value: WorkspaceSection.settings) {
                        Label(model.settings.language.tr(.settings), systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("PreviewX")
            .listStyle(.sidebar)
        } detail: {
            detail
        }
        .environment(\.locale, model.settings.language.locale)
        .preferredColorScheme(model.settings.appearance.colorScheme)
        .task { await model.bootstrap() }
        .onChange(of: model.settings.appearance) { _, _ in
            model.applyAppearance()
        }
        .onChange(of: model.currentURL) { _, newURL in
            if newURL != nil {
                section = .preview
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .preview:
            if let result = model.result {
                PreviewResultView(
                    result: result,
                    searchText: $model.searchText,
                    requestedLine: $model.requestedLine
                )
            } else if model.isLoading {
                ProgressView(model.settings.language.tr(.loadingPreview))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DropzoneWorkbenchView(model: model)
            }
        case .formats:
            FormatsAndRulesPane(model: model)
        case .settings:
            SettingsPane(model: model)
        }
    }
}

private enum WorkspaceSection: Hashable {
    case preview
    case formats
    case settings
}

private struct DropzoneWorkbenchView: View {
    @ObservedObject var model: PreviewWorkspaceModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 88, height: 88)
                Image(systemName: "sparkles.tv")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 8) {
                Text(model.settings.language.tr(.dropzoneTitle))
                    .font(.title2.weight(.bold))

                Text(model.settings.language.tr(.dropzoneSubtitle))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Button(action: model.openPanel) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text(model.settings.language.tr(.dropzoneOpenFile))
                }
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            HStack(spacing: 12) {
                FeatureBadge(icon: "lock.shield", text: model.settings.language.tr(.featureLocalOnly))
                FeatureBadge(icon: "bolt.fill", text: model.settings.language.tr(.featureZeroDep))
                FeatureBadge(icon: "eye.slash", text: model.settings.language.tr(.featureSafe))
            }
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

private struct FeatureBadge: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.secondary.opacity(0.08)))
    }
}

private struct FormatsAndRulesPane: View {
    @ObservedObject var model: PreviewWorkspaceModel
    @State private var searchText = ""

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.settings.language.tr(.formatsSubtitle))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            Section(model.settings.language.tr(.formatsAndRules)) {
                ForEach(categories) { cat in
                    FormatCategoryRow(
                        category: cat,
                        model: model,
                        isMatch: searchText.isEmpty || cat.matches(searchText)
                    )
                }
            }
        }
        .searchable(text: $searchText, prompt: model.settings.language.tr(.searchFormats))
        .navigationTitle(model.settings.language.tr(.formatsAndRules))
    }

    private var categories: [FormatCategory] {
        FormatCategory.makeCategories(language: model.settings.language)
    }
}

private struct FormatCategory: Identifiable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let color: Color
    let providerIDs: [String]
    let sampleExtensions: [String]

    func matches(_ query: String) -> Bool {
        let q = query.lowercased()
        if title.lowercased().contains(q) || description.lowercased().contains(q) { return true }
        return sampleExtensions.contains { $0.lowercased().contains(q) }
    }

    static func makeCategories(language: PreviewXSettings.Language) -> [FormatCategory] {
        [
            FormatCategory(
                id: "code",
                title: language.tr(.catCode),
                description: language.tr(.catCodeDesc),
                icon: "chevron.left.forwardslash.chevron.right",
                color: .blue,
                providerIDs: ["com.previewx.code"],
                sampleExtensions: ["swift", "py", "ts", "js", "go", "rs", "cpp", "c", "h", "java", "kt", "sh", "html", "css", "sql", "php"]
            ),
            FormatCategory(
                id: "structured",
                title: language.tr(.catStructured),
                description: language.tr(.catStructuredDesc),
                icon: "tablecells.badge.ellipsis",
                color: .orange,
                providerIDs: ["com.previewx.json", "com.previewx.xml", "com.previewx.yaml", "com.previewx.toml", "com.previewx.csv"],
                sampleExtensions: ["json", "json5", "xml", "yaml", "yml", "toml", "csv", "tsv"]
            ),
            FormatCategory(
                id: "archive",
                title: language.tr(.catArchives),
                description: language.tr(.catArchivesDesc),
                icon: "archivebox.fill",
                color: .indigo,
                providerIDs: ["com.previewx.archive"],
                sampleExtensions: ["zip", "tar", "gz", "tgz", "7z", "gzip"]
            ),
            FormatCategory(
                id: "documents",
                title: language.tr(.catDocs),
                description: language.tr(.catDocsDesc),
                icon: "doc.plaintext.fill",
                color: .teal,
                providerIDs: ["com.previewx.markdown", "com.previewx.text", "com.previewx.log"],
                sampleExtensions: ["md", "markdown", "mdown", "txt", "log", "out", "trace"]
            ),
            FormatCategory(
                id: "database",
                title: language.tr(.catDatabase),
                description: language.tr(.catDatabaseDesc),
                icon: "cylinder.split.1x2.fill",
                color: .purple,
                providerIDs: ["com.previewx.sqlite", "com.previewx.binary"],
                sampleExtensions: ["db", "sqlite", "sqlite3", "bin"]
            )
        ]
    }
}

private struct FormatCategoryRow: View {
    let category: FormatCategory
    @ObservedObject var model: PreviewWorkspaceModel
    let isMatch: Bool

    var body: some View {
        if isMatch {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: category.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(category.color)
                        .frame(width: 28, height: 28)
                        .background(category.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(category.title)
                                .font(.headline)
                            Spacer()
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { isCategoryEnabled },
                                    set: { setCategoryEnabled($0) }
                                )
                            )
                            .labelsHidden()
                        }

                        Text(category.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(category.sampleExtensions, id: \.self) { ext in
                            Text(".\(ext)")
                                .font(.caption2.monospaced())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.leading, 40)
            }
            .padding(.vertical, 6)
        }
    }

    private var isCategoryEnabled: Bool {
        for pid in category.providerIDs {
            if (model.settings.providerStates[pid]?.isEnabled ?? true) {
                return true
            }
        }
        return false
    }

    private func setCategoryEnabled(_ enabled: Bool) {
        for descriptor in model.providerDescriptors where category.providerIDs.contains(descriptor.id) {
            model.setProviderEnabled(descriptor, enabled: enabled)
        }
    }
}

private struct SettingsPane: View {
    @ObservedObject var model: PreviewWorkspaceModel

    private let byteLimits: [UInt64] = [
        1 * 1_024 * 1_024,
        2 * 1_024 * 1_024,
        4 * 1_024 * 1_024,
        8 * 1_024 * 1_024,
        16 * 1_024 * 1_024,
        32 * 1_024 * 1_024
    ]
    private let archiveLimits: [UInt64] = [1_000, 5_000, 10_000, 25_000, 50_000]
    private let lineLimits: [UInt64] = [5_000, 10_000, 20_000, 50_000]

    var body: some View {
        Form {
            Section {
                Picker(model.settings.language.tr(.language), selection: $model.settings.language) {
                    ForEach(PreviewXSettings.Language.allCases, id: \.self) { lang in
                        Text(lang.title).tag(lang)
                    }
                }
            } header: {
                Text(model.settings.language.tr(.language))
            } footer: {
                Text(model.settings.language.tr(.languageFooter))
            }

            Section {
                Picker(model.settings.language.tr(.theme), selection: $model.settings.appearance) {
                    ForEach(PreviewXSettings.Appearance.allCases, id: \.self) { appearance in
                        Text(appearance.localizedTitle(for: model.settings.language)).tag(appearance)
                    }
                }
            } header: {
                Text(model.settings.language.tr(.appearance))
            } footer: {
                Text(model.settings.language.tr(.themeFooter))
            }

            Section {
                Picker(model.settings.language.tr(.maxBytes), selection: $model.settings.policy.budget.maxBytesRead) {
                    ForEach(byteLimits, id: \.self) { limit in
                        Text(ByteFormatHelper.format(limit)).tag(limit)
                    }
                }
                Picker(model.settings.language.tr(.maxArchiveEntries), selection: $model.settings.policy.budget.maxArchiveEntries) {
                    ForEach(archiveLimits, id: \.self) { limit in
                        Text(limit.formatted()).tag(limit)
                    }
                }
                Picker(model.settings.language.tr(.maxTextLines), selection: $model.settings.policy.budget.maxTextLines) {
                    ForEach(lineLimits, id: \.self) { limit in
                        Text(limit.formatted()).tag(limit)
                    }
                }
            } header: {
                Text(model.settings.language.tr(.performance))
            } footer: {
                Text(model.settings.language.tr(.performanceFooter))
            }

            Section {
                Toggle(model.settings.language.tr(.inspectArchives), isOn: $model.settings.policy.allowArchiveInspection)
                Toggle(model.settings.language.tr(.redactSecrets), isOn: $model.settings.policy.redactSecrets)
            } header: {
                Text(model.settings.language.tr(.security))
            } footer: {
                Text(model.settings.language.tr(.securityFooter))
            }

            Section {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("PreviewX")
                                .font(.headline)
                            Text("v1.0.0")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                        }
                        Text(model.settings.language.tr(.aboutSubtitle))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Text(model.settings.language.tr(.designedAndDevelopedBy))
                                .foregroundStyle(.secondary)
                            Text("idcpj")
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                        }
                        .font(.caption2)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            } header: {
                Text(model.settings.language.tr(.about))
            }

            Section {
                Button(model.settings.language.tr(.resetSettings), role: .destructive, action: model.resetSettings)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: model.settings) { _, _ in model.saveSettings() }
        .navigationTitle(model.settings.language.tr(.settings))
    }
}

private extension PreviewXSettings.Appearance {
    func localizedTitle(for language: PreviewXSettings.Language) -> String {
        switch self {
        case .system: language.tr(.themeSystem)
        case .light: language.tr(.themeLight)
        case .dark: language.tr(.themeDark)
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
