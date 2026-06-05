import PocketCastsServer
import UIKit

class EmailHelper: NSObject {
    /// Opens the Pocket Casts support site. (Previously routed to the in-app Zendesk
    /// messaging flow, which has been removed.)
    func presentSupportDialog(_ source: UIViewController) {
        DispatchQueue.main.async {
            guard let url = URL(string: ServerConstants.Urls.support) else { return }
            URLHelper.open(url, context: .trustedDocumentation, from: source)
        }
    }
}
