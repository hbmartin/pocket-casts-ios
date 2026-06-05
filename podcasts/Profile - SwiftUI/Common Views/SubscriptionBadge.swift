import SwiftUI
import PocketCastsServer

struct SubscriptionBadge: View {
    let tier: SubscriptionTier
    var displayMode: DisplayMode = .black
    var foregroundColor: Color? = nil

    /// The base of the font the label should use
    var fontSize: Double = 14

    var body: some View {
        EmptyView()
    }

    enum DisplayMode {
        case black
        case gradient
        case plain
    }
}
