import UIKit

class SmartInvertImageView: UIImageView {
    override nonisolated func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated {

            accessibilityIgnoresInvertColors = true
        }
    }
}
