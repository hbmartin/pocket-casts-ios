
import UIKit

@MainActor
protocol AutoScrollCollectionViewDelegate: UICollectionView {
    var timer: Timer? { get set }
    func initializeAutoScrollTimer()
    func scrolltoNextItem()
    func stopAutoScrollTimer()
}

class ThemeableCollectionView: UICollectionView, AutoScrollCollectionViewDelegate {
    var style: ThemeStyle = .primaryUi04 {
        didSet {
            updateColor()
        }
    }

    private var themeToken: NotificationCenter.ObservationToken?

    override nonisolated func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated {
            themeToken = NotificationCenter.default.addObserver(for: ThemeChanged.self) { [weak self] _ in
                self?.updateColor()
            }
            updateColor()
        }
    }

    deinit {
        let token = themeToken
        NotificationCenter.default.removeObserver(self)
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func updateColor() {
        backgroundColor = AppTheme.colorForStyle(style)
        indicatorStyle = AppTheme.indicatorStyle()
    }

   // MARK: - Auto scroll handling
    var timer: Timer?

    func initializeAutoScrollTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: 3.0, target: self, selector: #selector(scrolltoNextItem), userInfo: nil, repeats: true)
    }

    @objc func scrolltoNextItem() {
        let nextIndex = (indexPathsForVisibleItems.last?.item ?? 0) + 1
        let indexPath = IndexPath(item: nextIndex, section: 0)
        if nextIndex < numberOfItems(inSection: 0) {
            scrollToItem(at: indexPath, at: .left, animated: true)
        } else if numberOfItems(inSection: 0) > 0 {
            scrollToItem(at: IndexPath(item: 0, section: 0), at: .left, animated: false)
        }
    }

    func stopAutoScrollTimer() {
        timer?.invalidate()
        timer = nil
    }
}
