import PocketCastsDataModel
import UIKit

/// Builds the highlight editor sheet (Highlights program S4). One factory so
/// every entry point — bookmark lists, the capture toast, review-after-capture —
/// presents the same configuration.
@MainActor
enum HighlightEditorPresenter {
    /// - Parameter onDismiss: called after the sheet closes, whether saved or
    ///   cancelled (list reloads hang off the manager's change events instead).
    static func controller(
        manager: BookmarkManager,
        bookmark: Bookmark,
        source: BookmarkAnalyticsSource,
        onDismiss: (() -> Void)? = nil
    ) -> UIViewController {
        let model = HighlightEditorViewModel(manager: manager, bookmark: bookmark)
        model.analyticsSource = source

        let controller = ThemedHostingController(rootView: HighlightEditorView(model: model))
        model.onDismiss = { [weak controller] in
            controller?.dismiss(animated: true)
            onDismiss?()
        }

        Analytics.track(.highlightEditorShown, properties: ["source": source.rawValue])
        return controller
    }
}
