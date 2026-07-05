import UIKit

class SiriShortcutSuggestedCell: ThemeableCell {
    @IBOutlet var addIcon: TintableImageView! {
        didSet {
            addIcon.tintColor = ThemeColor.primaryInteractive01()
            updateSize()
        }
    }

    @IBOutlet var titleLabel: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        // awakeFromNib is nonisolated in its ObjC declaration, but views always wake on the main thread
        MainActor.assumeIsolated {
            _ = registerForPreferredContentSizeCategoryChanges { $0.updateSize() }
        }
    }

    private func updateSize() {
        let iconMetric = UIFontMetrics(forTextStyle: .largeTitle)
        let iconSize = max(24, iconMetric.scaledValue(for: 24))
        addIcon.updateSizeConstraints(to: iconSize)
    }
}
