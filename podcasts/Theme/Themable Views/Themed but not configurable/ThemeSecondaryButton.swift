import UIKit

class ThemeSecondaryButton: UIButton {
    override nonisolated func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated {
            themeToken = NotificationCenter.default.addObserver(for: ThemeChanged.self) { [weak self] _ in
                self?.setTintColorForTheme()
            }
            setTintColorForTheme()
        }
    }

    private var themeToken: NotificationCenter.ObservationToken?

    deinit {
        let token = themeToken
        NotificationCenter.default.removeObserver(self)
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func setTintColorForTheme() {
        tintColor = ThemeColor.primaryIcon02()
    }
}
