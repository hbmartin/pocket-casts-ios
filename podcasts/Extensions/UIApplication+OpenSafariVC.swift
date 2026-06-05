import UIKit

extension UIApplication {
    /// Opens external content with URLHelper, respecting the user's external browser preference.
    /// - Parameter url: The url to attempt to open
    func openSafariVCIfPossible(_ url: URL) {
        URLHelper.open(
            url,
            context: .externalContent,
            options: .init(
                prefersExternalBrowser: Settings.openLinks
            )
        )
    }
}
