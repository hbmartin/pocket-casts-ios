import Foundation

extension UIScrollView {
    func applyInsetForMiniPlayer(additionalBottomInset: CGFloat = 0) {
        // On iOS 26 the mini player is a `UITabAccessory` that manages its own bottom safe-area
        // inset, so no manual content inset is applied here.
    }

    func updateContentInset(multiSelectEnabled: Bool) {
        let multiSelectFooterOffset: CGFloat = multiSelectEnabled ? 60 : 0
        contentInset.bottom = multiSelectFooterOffset
        verticalScrollIndicatorInsets.bottom = multiSelectFooterOffset
    }
}
