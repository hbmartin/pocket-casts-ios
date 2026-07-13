import UIKit

class TopShadowView: ThemeableView {
    var hideShadow = false {
        didSet {
            layoutIfNeeded()
        }
    }

    override func layoutSubviews() {
        if hideShadow {
            layer.shadowRadius = 0
        } else {
            layer.masksToBounds = false
            // Themed: dark themes get a lighter shadow so the edge stays visible.
            layer.shadowColor = ThemeColor.primaryUi05().cgColor
            layer.shadowOffset = CGSize(width: 0, height: -2)
            layer.shadowOpacity = 0.15
            layer.shadowRadius = 2
        }
    }

    override func handleThemeDidChange() {
        setNeedsLayout()
    }
}
