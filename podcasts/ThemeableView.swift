import UIKit

class ThemeableView: UIView {
    var style: ThemeStyle = .primaryUi01 {
        didSet {
            updateColor()
        }
    }

    var themeOverride: Theme.ThemeType? {
        didSet {
            updateColor()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        setup()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        setup()
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
            self?.themeDidChange()
        }
    }

    private func themeDidChange() {
        updateColor()
        handleThemeDidChange()
    }

    // For subclasses to be notified about theme changes
    func handleThemeDidChange() {}

    private func updateColor() {
        backgroundColor = AppTheme.colorForStyle(style, themeOverride: themeOverride)
    }
}
