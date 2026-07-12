import UIKit

class ThemeLoadingIndicator: UIActivityIndicatorView {
    override nonisolated func awakeFromNib() {
        super.awakeFromNib()

        MainActor.assumeIsolated {
            themeToken = NotificationCenter.default.addObserver(for: ThemeChanged.self) { [weak self] _ in
                self?.setThemeColor()
            }
            setThemeColor()
        }
    }

    private var themeToken: NotificationCenter.ObservationToken?

    private func setThemeColor() {
        color = AppTheme.loadingActivityColor()
    }

    deinit {
        let token = themeToken
        NotificationCenter.default.removeObserver(self)
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
