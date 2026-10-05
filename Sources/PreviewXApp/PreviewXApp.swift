import AppKit
import PreviewXUI
import SwiftUI

@MainActor
final class PreviewXAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        setupApplicationIcon()
    }

    private func setupApplicationIcon() {
        if let bundleIconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: bundleIconURL) {
            NSApp.applicationIconImage = image
            return
        }
        let fallbackIconURL = URL(fileURLWithPath: "App/AppIcon.icns")
        if FileManager.default.fileExists(atPath: fallbackIconURL.path),
           let image = NSImage(contentsOf: fallbackIconURL) {
            NSApp.applicationIconImage = image
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct PreviewXApp: App {
    @NSApplicationDelegateAdaptor(PreviewXAppDelegate.self) private var appDelegate
    @StateObject private var workspace = PreviewWorkspaceModel()
    @State private var didHandleInitialFile = false

    var body: some Scene {
        WindowGroup {
            PreviewWorkspaceView(model: workspace)
                .frame(minWidth: 920, minHeight: 620)
                .preferredColorScheme(workspace.settings.appearance == .light ? .light : workspace.settings.appearance == .dark ? .dark : nil)
                .onOpenURL { workspace.preview(url: $0) }
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    previewInitialFileIfPresent()
                }
        }
        .defaultSize(width: 1100, height: 720)
    }

    private func previewInitialFileIfPresent() {
        guard !didHandleInitialFile else { return }
        didHandleInitialFile = true
        guard let fileArgument = CommandLine.arguments.dropFirst().first(where: { argument in
            !argument.hasPrefix("-") && FileManager.default.fileExists(atPath: argument)
        }) else { return }
        workspace.preview(url: URL(fileURLWithPath: fileArgument))
    }
}
