import PocketCastsDataModel
import UIKit

@MainActor
protocol BookmarkListRouter: AnyObject {
    func bookmarkPlay(_ bookmark: Bookmark)
    func bookmarkEdit(_ bookmark: Bookmark)
    func bookmarkShare(_ bookmark: Bookmark)

    /// Optional: Dismisses the presented bookmark list, if applicable.
    func dismissBookmarksList()

    /// Called when a view model needs to present a view controller, such as an alert.
    func presentBookmarkController(_ controller: UIViewController)
}

extension BookmarkListRouter {
    func dismissBookmarksList() { /* NOOP */ }
}

// MARK: - UIViewController subclass default implementation

extension BookmarkListRouter where Self: UIViewController {
    func presentBookmarkController(_ controller: UIViewController) {
        if let popover = controller.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        present(controller, animated: true)
    }
}
