
import UIKit

class ThemeableLabel: UILabel {
    var style: ThemeStyle = .primaryText01 {
        didSet {
            updateTextColor()
        }
    }

    var themeOverride: Theme.ThemeType? {
        didSet {
            updateTextColor()
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

    override nonisolated func awakeFromNib() {
        super.awakeFromNib()

        // awakeFromNib is nonisolated in its ObjC declaration, but views always wake on the main thread
        MainActor.assumeIsolated {
            updateTextColor()
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
        themeToken = NotificationCenter.default.addObserver(for: ThemeChanged.self) { [weak self] _ in
            self?.themeDidChange()
        }
        updateTextColor()
    }

    private func themeDidChange() {
        updateTextColor()
        handleThemeDidChange()
    }

    // can be overridden by sub-classes to do more when the theme changes
    func handleThemeDidChange() {}

    private func updateTextColor() {
        textColor = AppTheme.colorForStyle(style, themeOverride: themeOverride)
    }
}
