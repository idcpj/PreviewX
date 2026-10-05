import AppKit
import PreviewXCore
import PreviewXUI
import QuickLookUI
import SwiftUI

@objc(PreviewViewController)
@MainActor
public final class PreviewViewController: NSViewController, QLPreviewingController {
    private let workspace = PreviewWorkspaceModel()

    public override func loadView() {
        let hosting = NSHostingView(rootView: QuickLookRootView(model: workspace))
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 640)
        view = hosting
        preferredContentSize = CGSize(width: 900, height: 640)
    }

    public func preparePreviewOfFile(at url: URL) async throws {
        await workspace.bootstrap()
        await workspace.previewImmediately(url: url)
        switch workspace.result {
        case let .failed(error):
            throw error
        case let .unsupported(reason):
            throw PreviewError(.unsupported, reason)
        case .success, .partial, .none:
            break
        }
    }
}

private struct QuickLookRootView: View {
    @ObservedObject var model: PreviewWorkspaceModel
    @State private var searchText = ""
    @State private var requestedLine: Int?

    var body: some View {
        Group {
            if let result = model.result {
                PreviewResultView(
                    result: result,
                    searchText: $searchText,
                    requestedLine: $requestedLine
                )
            } else {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}
