import UIKit

extension UIViewController {
    /// Hides or shows the enclosing tab bar. When the view controller isn't inside a
    /// tab bar controller, this is a no-op.
    func setEnclosingTabBarHidden(_ hidden: Bool, animated: Bool) {
        guard let tabBarController else { return }
        tabBarController.setTabBarHidden(hidden, animated: animated)
    }
}
