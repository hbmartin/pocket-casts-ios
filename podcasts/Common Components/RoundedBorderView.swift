
import UIKit
@IBDesignable
class RoundedBorderView: UIView {
    @IBInspectable var cornerRadius: CGFloat = 4 {
        didSet {
            setupBorder()
        }
    }

    var getBorderColor: (() -> UIColor) = { AppTheme.tableDividerColor() } {
        didSet {
            setupBorder()
        }
    }

    var getBgColor: (() -> UIColor) = { UIColor.clear } {
        didSet {
            setupBorder()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        setupBorder()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        setupBorder()
    }

    private var themeToken: NotificationCenter.ObservationToken?

    deinit {
        let token = themeToken
        NotificationCenter.default.removeObserver(self)
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func setupBorder() {
        clipsToBounds = true

        updateColors()
        layer.borderWidth = 1.0 / UIScreen.main.scale
        layer.cornerRadius = cornerRadius

        if themeToken == nil {
            themeToken = NotificationCenter.default.addObserver(for: ThemeChanged.self) { [weak self] _ in
                self?.updateColors()
            }
        }
    }

    private func updateColors() {
        layer.borderColor = getBorderColor().cgColor
        backgroundColor = getBgColor()
    }
}
