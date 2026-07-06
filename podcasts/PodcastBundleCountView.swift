import UIKit

class BundleHeartCountView: PodcastHeartView {
    var countLabel: ThemeableLabel!

    override nonisolated func awakeFromNib() {
        super.awakeFromNib()
        // awakeFromNib is nonisolated in its ObjC declaration, but views always wake on the main thread
        MainActor.assumeIsolated {
            countLabel = ThemeableLabel()
            countLabel.style = .primaryInteractive02
            countLabel.textAlignment = .center
            countLabel.font = UIFont.systemFont(ofSize: 14, weight: .bold)
            addSubview(countLabel)
            countLabel.anchorToAllSidesOf(view: self)
            countLabel.isHidden = true
        }
    }

    func setBundleCount(_ count: Int) {
        guard count > 0 else {
            heartImageView.isHidden = false
            countLabel.isHidden = true
            return
        }
        heartImageView.isHidden = true
        countLabel.isHidden = false
        countLabel.text = "\(count)"
    }
}
