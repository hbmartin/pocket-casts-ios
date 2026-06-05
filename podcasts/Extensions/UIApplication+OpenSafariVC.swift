import UIKit

extension UIApplication {
    /// Opens SFSafariViewController if the URL scheme is http or https. If not, opens using UIApplication.open(url)
    /// - Parameter url: The url to attempt to open
    func openSafariVCIfPossible(_ url: URL) {
        URLHelper.open(
            url,
            context: .externalContent,
            from: SceneHelper.rootViewController(),
            allowsExternalFallback: true
        )
    }
}
