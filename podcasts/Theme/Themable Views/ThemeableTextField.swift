import UIKit

class ThemeableTextField: UITextField {
    var textStyle: ThemeStyle = .primaryText01 {
        didSet {
            updateColor()
        }
    }

    var backgroundStyle: ThemeStyle? {
        didSet {
            updateColor()
        }
    }

    var placeholderStyle: ThemeStyle = .primaryText02 {
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
            self?.updateColor()
        }
    }

    private func updateColor() {
        textColor = AppTheme.colorForStyle(textStyle)
        if let placeholder {
            attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [NSAttributedString.Key.foregroundColor: AppTheme.colorForStyle(placeholderStyle).withAlphaComponent(0.5)])
        }
        if let background = backgroundStyle {
            backgroundColor = AppTheme.colorForStyle(background)
        } else {
            backgroundColor = UIColor.clear
        }

        keyboardAppearance = AppTheme.keyboardAppearance()
    }
}
