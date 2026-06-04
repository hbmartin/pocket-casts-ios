import PocketCastsServer
import SafariServices
import UIKit

class EmailHelper: NSObject {
    /// Opens the Pocket Casts support site. (Previously routed to the in-app Zendesk
    /// messaging flow, which has been removed.)
    func presentSupportDialog(_ source: UIViewController) {
        DispatchQueue.main.async {
            guard let url = URL(string: ServerConstants.Urls.support) else { return }
            let safari = SFSafariViewController(url: url)
            source.present(safari, animated: true, completion: nil)
        }
    }
}
