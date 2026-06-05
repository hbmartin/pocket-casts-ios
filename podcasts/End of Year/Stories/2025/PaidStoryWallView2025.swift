import SwiftUI

import EndOfYear
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
                DispatchQueue.main.async {
                    advanceToNextStory()
                }
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
        .environmentObject(StoriesModel(dataSource: EndOfYearStoriesDataSource(model: EndOfYear2025StoriesModel()), configuration: StoriesConfiguration()))
}
