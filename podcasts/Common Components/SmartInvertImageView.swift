import UIKit

class SmartInvertImageView: UIImageView {
    override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated {

            accessibilityIgnoresInvertColors = true
        }
    }
}
