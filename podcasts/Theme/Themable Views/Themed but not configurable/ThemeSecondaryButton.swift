import UIKit

class ThemeSecondaryButton: UIButton {
    override nonisolated func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated {
            NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: Constants.Notifications.themeChanged, object: nil)
            setTintColorForTheme()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func themeDidChange() {
        setTintColorForTheme()
    }

    private func setTintColorForTheme() {
        tintColor = ThemeColor.primaryIcon02()
    }
}
