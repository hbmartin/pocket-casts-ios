import UIKit

class ThemeableTextView: UITextView {
    var textStyle: ThemeStyle = .primaryText01 {
        didSet {
            updateColor()
        }
    }

    var backgroundStyle: ThemeStyle = .primaryUi01 {
        didSet {
            updateColor()
        }
    }

    override nonisolated func awakeFromNib() {
        super.awakeFromNib()

        MainActor.assumeIsolated {
            setup()
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

    private func setup() {
        updateColor()

        themeToken = NotificationCenter.default.addObserver(for: ThemeChanged.self) { [weak self] _ in
            self?.updateColor()
        }
    }

    private func updateColor() {
        textColor = AppTheme.colorForStyle(textStyle)
        backgroundColor = AppTheme.colorForStyle(backgroundStyle)
    }
}
