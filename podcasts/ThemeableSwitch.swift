import UIKit

class ThemeableSwitch: UISwitch {
    var onStyle: ThemeStyle = .primaryInteractive01 {
        didSet {
            updateColors()
        }
    }

    var thumbStyle: ThemeStyle = .primaryInteractive02 {
        didSet {
            updateColors()
        }
    }

    var offStyle: ThemeStyle = .primaryInteractive03 {
        didSet {
            updateColors()
        }
    }

    var themeOverride: Theme.ThemeType? {
        didSet {
            updateColors()
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
        layer.cornerRadius = 16
        updateColors()

        themeToken = NotificationCenter.default.addObserver(for: ThemeChanged.self) { [weak self] _ in
            self?.updateColors()
        }
    }

    private func updateColors() {
        onTintColor = AppTheme.colorForStyle(onStyle, themeOverride: themeOverride)
        thumbTintColor = AppTheme.colorForStyle(thumbStyle, themeOverride: themeOverride)
        backgroundColor = AppTheme.colorForStyle(offStyle, themeOverride: themeOverride)
    }
}
