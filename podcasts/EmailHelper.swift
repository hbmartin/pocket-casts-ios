import PocketCastsServer
import UIKit

class EmailHelper: NSObject {
    /// Opens the Pocket Casts support site. (Previously routed to an in-app
    /// support messaging flow, which has been removed.)
    func presentSupportDialog(_ source: UIViewController) {
        DispatchQueue.main.async {
            guard let url = URL(string: ServerConstants.Urls.support) else { return }
            URLHelper.open(url, context: .trustedDocumentation, options: .init(presenter: source))
        }
    }
}
