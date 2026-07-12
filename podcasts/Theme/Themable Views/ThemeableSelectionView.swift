import UIKit

class ThemeableSelectionView: UIView {
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

    var isSelected: Bool = false {
        didSet {
            updateColor()
            updateAccessibilityTraits()
        }
    }

    var selectedStyle: ThemeStyle = .primaryField03Active {
        didSet {
            updateColor()
        }
    }

    var unselectedStyle: ThemeStyle = .primaryField03 {
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
        backgroundColor = AppTheme.colorForStyle(style, themeOverride: themeOverride)
        layer.borderColor = isSelected ? AppTheme.colorForStyle(selectedStyle, themeOverride: themeOverride).cgColor : AppTheme.colorForStyle(unselectedStyle, themeOverride: themeOverride).cgColor
    }

    private func updateAccessibilityTraits() {
        if isSelected {
            accessibilityTraits.insert(.selected)
        } else {
            accessibilityTraits.remove(.selected)
        }
    }
}
