import UIKit

class ThemeableRoundedButton: UIButton {
    var buttonStyle: ThemeStyle = .primaryInteractive01 {
        didSet {
            updateColor()
        }
    }

    var textStyle: ThemeStyle = .primaryUi01 {
        didSet {
            updateColor()
        }
    }

    var shouldFill = true {
        didSet {
            updateColor()
        }
    }

    var themeOverride: Theme.ThemeType? {
        didSet {
            updateColor()
        }
    }

    @IBInspectable public var cornerRadius: CGFloat = 12 {
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

    private func setup() {
        themeToken = NotificationCenter.default.addObserver(for: ThemeChanged.self) { [weak self] _ in
            self?.themeDidChange()
        }
        updateColor()
    }

    deinit {
        let token = themeToken
        NotificationCenter.default.removeObserver(self)
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func themeDidChange() {
        updateColor()
    }

    func updateColor() {
        layer.cornerRadius = cornerRadius

        if shouldFill {
            backgroundColor = AppTheme.colorForStyle(buttonStyle, themeOverride: themeOverride)
            setTitleColor(AppTheme.colorForStyle(textStyle, themeOverride: themeOverride), for: .normal)
            tintColor = titleColor(for: .normal)
            layer.borderWidth = 0
        } else {
            backgroundColor = AppTheme.colorForStyle(textStyle, themeOverride: themeOverride)
            setTitleColor(AppTheme.colorForStyle(buttonStyle, themeOverride: themeOverride), for: .normal)
            tintColor = titleColor(for: .normal)
            layer.borderColor = AppTheme.colorForStyle(buttonStyle, themeOverride: themeOverride).cgColor
            layer.borderWidth = 2
        }
    }
}
