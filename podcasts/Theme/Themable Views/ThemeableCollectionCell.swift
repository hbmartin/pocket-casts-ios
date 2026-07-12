import UIKit

class ThemeableCollectionCell: UICollectionViewCell {
    var style: ThemeStyle = .primaryUi02 {
        didSet {
            updateColor(AppTheme.colorForStyle(style))
        }
    }

    private var reorderHandle: CellReorderHandleView?

    var showsReorderHandle: Bool {
        get { reorderHandle?.isVisible ?? false }
        set {
            guard newValue else {
                reorderHandle?.isVisible = false
                return
            }
            if reorderHandle == nil {
                let handle = CellReorderHandleView(maskedView: contentView)
                addSubview(handle)
                handle.anchorToAllSidesOf(view: self)
                reorderHandle = handle
            }
            reorderHandle?.isVisible = true
        }
    }

    private var themeToken: NotificationCenter.ObservationToken?

    override nonisolated func awakeFromNib() {
        super.awakeFromNib()

        MainActor.assumeIsolated {
            themeToken = NotificationCenter.default.addObserver(for: ThemeChanged.self) { [weak self] _ in
                self?.themeDidChange()
            }
            updateColor(AppTheme.colorForStyle(style))
        }
    }

    deinit {
        let token = themeToken
        NotificationCenter.default.removeObserver(self)
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func themeDidChange() {
        updateColor(AppTheme.colorForStyle(style))
        reorderHandle?.themeDidChange()
        handleThemeDidChange()
    }

    func handleThemeDidChange() {}

    private func updateColor(_ color: UIColor) {
        contentView.backgroundColor = color
        backgroundColor = color
    }
}
