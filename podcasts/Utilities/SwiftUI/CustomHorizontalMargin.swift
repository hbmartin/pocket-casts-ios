import SwiftUI

struct CustomHorizontalMargin: ViewModifier {
    let margin: CGFloat

    func body(content: Content) -> some View {
        content.contentMargins(.horizontal, margin, for: .scrollContent)
    }
}

extension View {
    func customHorizontalMargin(margin: CGFloat)
    -> some View {
        modifier(CustomHorizontalMargin(margin: margin))
  }
}
