import UIKit

class ThemeLoadingIndicator: UIActivityIndicatorView {
    override func awakeFromNib() {
        super.awakeFromNib()

        MainActor.assumeIsolated {
            NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: Constants.Notifications.themeChanged, object: nil)
            setThemeColor()
        }
    }

    @objc private func themeDidChange() {
        setThemeColor()
    }

    private func setThemeColor() {
        color = AppTheme.loadingActivityColor()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
