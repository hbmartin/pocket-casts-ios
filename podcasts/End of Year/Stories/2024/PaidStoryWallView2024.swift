import SwiftUI
import PocketCastsServer

struct PaidStoryWallView2024: View {
    init(subscriptionTier: SubscriptionTier) {
        _ = subscriptionTier
    }

    var body: some View {
        EmptyView()
    }
}

#Preview {
    PaidStoryWallView2024(subscriptionTier: .none)
}
