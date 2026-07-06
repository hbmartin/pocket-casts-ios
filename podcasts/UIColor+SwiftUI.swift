import Foundation
import SwiftUI

nonisolated extension UIColor {
    var color: Color {
        Color(self)
    }
}

extension ThemeColor {
    /// Always `nil` on iOS 26: navigation bar buttons adopt the system Liquid Glass tint rather
    /// than a flat themed color. The `color` argument is retained for call-site compatibility.
    static func navBarTint(_ color: UIColor) -> Color? {
        nil
    }
}
