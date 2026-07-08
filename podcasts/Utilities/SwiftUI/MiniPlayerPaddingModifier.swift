import SwiftUI

/// Apply a bottom padding whenever the mini player is visible
public struct MiniPlayerSafeAreaInset: ViewModifier {
    let multipler: CGFloat

    init(multipler: CGFloat) {
        self.multipler = multipler
    }

    public func body(content: Content) -> some View {
        // On iOS 26 the mini player is presented as a `UITabAccessory`, which manages its own
        // bottom safe-area inset, so this modifier is now a pass-through kept for call-site
        // compatibility.
        content
    }
}

// Create an extension for easier usage
public extension View {
    func miniPlayerSafeAreaInset(multiplier: CGFloat = 1) -> some View {
        self.modifier(MiniPlayerSafeAreaInset(multipler: multiplier))
    }
}
