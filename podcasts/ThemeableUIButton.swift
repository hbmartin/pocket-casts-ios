
import UIKit

class ThemeableUIButton: UIButton {
    var style: ThemeStyle = .primaryInteractive01 {
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

    override nonisolated func awakeFromNib() {
        super.awakeFromNib()

        // awakeFromNib is nonisolated in its ObjC declaration, but views always wake on the main thread
        MainActor.assumeIsolated {
            updateColors()
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
        updateColors()
    }

    private func themeDidChange() {
        updateColors()
        handleThemeDidChange()
    }

    // can be overridden by sub-classes to do more when the theme changes
    func handleThemeDidChange() {}

    private func updateColors() {
        let color = AppTheme.colorForStyle(style)

        // we use both these methods because setTitleColor seems to work for the initial state and changing the label for changes from then on
        setTitleColor(color, for: .normal)
        titleLabel?.textColor = color

        imageView?.tintColor = color
    }
}
