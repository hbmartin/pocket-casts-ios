import PocketCastsServer
import SwiftUI

struct BookmarksLockedStateView<Style: EmptyStateViewStyle>: View {
    @EnvironmentObject var viewModel: BookmarkListViewModel
    @ObservedObject var style: Style

    private var title: String = L10n.noBookmarksTitle
    private var message: String = L10n.noBookmarksLockedMessage
    private var actionTitle: String = L10n.noBookmarksLockedButtonTitle

    init(style: Style, feature: PaidFeature, source: BookmarkAnalyticsSource) {
        self.style = style
    }

    var body: some View {
        EmptyStateView(title: title, message: message, icon: { Image("bookmarks-profile") }, actions: [], style: style, maxContentWidth: .infinity)
    }
}

/// Bookmarks are now free, so this no longer presents any upgrade UI.
class BookmarksUpgradeViewModel: ObservableObject {
    let feature: PaidFeature
    let bookmarksSource: BookmarkAnalyticsSource
    let upgradeSource: PlusUpgradeViewSource

    init(feature: PaidFeature, source: BookmarkAnalyticsSource, upgradeSource: PlusUpgradeViewSource = .bookmarksLocked) {
        self.feature = feature
        self.bookmarksSource = source
        self.upgradeSource = upgradeSource
    }

    var upgradeLabel: String {
        L10n.upgradeToPlan(feature.tier == .patron ? L10n.patron : L10n.pocketCastsPlusShort)
    }

    func upgradeTapped() {
        Analytics.track(.bookmarksGetBookmarksButtonTapped, source: bookmarksSource)
        showUpgrade()
    }

    func showUpgrade() {
        // No-op: bookmarks are free, there is no upgrade flow to present.
    }
}
