
import UIKit

class ThemeDividerView: UIView {
    var style: ThemeStyle = .primaryUi05 {
        didSet {
            setBgColorForTheme()
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

    var themeOverride: Theme.ThemeType? {
        didSet {
            setBgColorForTheme()
        }
    }

    private var themeToken: NotificationCenter.ObservationToken?

    private func setup() {
        setBgColorForTheme()

        themeToken = NotificationCenter.default.addObserver(for: ThemeChanged.self) { [weak self] _ in
            self?.setBgColorForTheme()
        }
    }

    deinit {
        let token = themeToken
        NotificationCenter.default.removeObserver(self)
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func setBgColorForTheme() {
        backgroundColor = AppTheme.colorForStyle(style, themeOverride: themeOverride)
    }
}
