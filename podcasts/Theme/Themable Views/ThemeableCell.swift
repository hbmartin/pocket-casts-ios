import UIKit

class ThemeableCell: UITableViewCell, ReusableTableCell {
    var style: ThemeStyle = .primaryUi02 {
        didSet {
            updateColor()
        }
    }

    var selectedStyle: ThemeStyle = .primaryUi02Active
    var iconStyle: ThemeStyle = .primaryIcon02
    var themeOverride: Theme.ThemeType? {
        didSet {
            updateColor()
        }
    }

    private var themeToken: NotificationCenter.ObservationToken?

    override nonisolated func awakeFromNib() {
        super.awakeFromNib()

        MainActor.assumeIsolated {
            observeThemeChanges()
            updateColor()
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        observeThemeChanges()
        updateColor()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit {
        let token = themeToken
        NotificationCenter.default.removeObserver(self)
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func observeThemeChanges() {
        guard themeToken == nil else { return }

        themeToken = NotificationCenter.default.addObserver(for: ThemeChanged.self) { [weak self] _ in
            self?.updateColor()
        }
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        setHighlightedState(highlighted)
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        setHighlightedState(selected)
    }

    func handleThemeDidChange() {}

    func updateColor() {
        updateBgColor(AppTheme.colorForStyle(style, themeOverride: themeOverride))
        accessoryView?.tintColor = AppTheme.colorForStyle(iconStyle, themeOverride: themeOverride)
        tintColor = AppTheme.colorForStyle(iconStyle, themeOverride: themeOverride)

        handleThemeDidChange()
    }

    private func setHighlightedState(_ highlighted: Bool) {
        if highlighted {
            updateBgColor(AppTheme.colorForStyle(selectedStyle, themeOverride: themeOverride))
        } else {
            updateBgColor(AppTheme.colorForStyle(style, themeOverride: themeOverride))
        }
    }

    private func updateBgColor(_ color: UIColor) {
        contentView.backgroundColor = color
        backgroundColor = color
        accessoryView?.backgroundColor = color
    }
}
