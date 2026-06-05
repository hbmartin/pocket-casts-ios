import SwiftUI

import PocketCastsServer

struct PaidStoryWallView2025: StoryView {
    let identifier = "plus_interstitial"

    @EnvironmentObject var storyModel: StoriesModel

    var shouldPause: Bool = true

    let plusOnly = false

    init(subscriptionTier: SubscriptionTier) {
        _ = subscriptionTier
    }

    var body: some View {
        Color.clear
            .onAppear {
                advanceToNextStory()
            }
    }

    private func advanceToNextStory() {
        storyModel.start()
        storyModel.next()
    }

    func onAppear() {
        Analytics.track(.endOfYearStoryShown, story: identifier)
    }
}

#Preview("None") {
    PaidStoryWallView2025(subscriptionTier: .none)
}
