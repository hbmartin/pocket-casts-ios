import SwiftUI
import PocketCastsServer
import PocketCastsUtils

/// The friends activity feed embedded at the top of the Explore tab (Slice 5,
/// ADR-0009: items are derived at read time from followees' rows, already
/// visibility-gated and mute-filtered server-side). Joined users see the feed
/// plus a find-people row; everyone else sees a join card above the unchanged
/// directory. The tab keeps the name "Explore" (amended decision 8).
struct SocialFeedSection: View {
    @EnvironmentObject var theme: Theme
    @StateObject var viewModel: SocialFeedViewModel

    var body: some View {
        Group {
            if viewModel.isJoined {
                feedContent
            } else {
                joinCard
            }
        }
        .task { await viewModel.load() }
        .onAppear { Task { await viewModel.refreshIfStale() } }
    }

    // MARK: - Feed (joined)

    private var feedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.socialFeedHeader)
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.color(for: .primaryText01, theme: theme))
                Spacer()
                Button {
                    SocialCoordinator.openFindPeople()
                } label: {
                    Label(L10n.socialFindPeople, systemImage: "person.badge.plus")
                        .font(.subheadline)
                        .labelStyle(.titleAndIcon)
                }
            }
            .padding(.horizontal, 16)

            if viewModel.items.isEmpty {
                if !viewModel.isLoading {
                    Text(L10n.socialFeedEmpty)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.items) { item in
                        FeedItemRow(item: item) {
                            viewModel.open(item)
                        }
                        if item.id != viewModel.items.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }

            // Trending with friends (Slice 10): followees' recent listening,
            // history-visibility gated server-side. Hidden when empty.
            if !viewModel.trending.isEmpty {
                Text(L10n.socialTrendingHeader)
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.color(for: .primaryText01, theme: theme))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                VStack(spacing: 0) {
                    ForEach(viewModel.trending) { podcast in
                        Button {
                            viewModel.openTrending(podcast)
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(podcast.title.isEmpty ? podcast.podcastUuid : podcast.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(AppTheme.color(for: .primaryText01, theme: theme))
                                        .lineLimit(1)
                                    HStack(spacing: 4) {
                                        if !podcast.author.isEmpty {
                                            Text(podcast.author)
                                            Text("·")
                                        }
                                        Text(L10n.socialTrendingListeners(podcast.listenerCount))
                                    }
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                                    .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.color(for: .primaryIcon02, theme: theme))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if podcast.id != viewModel.trending.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Join card (not joined)

    private var joinCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.socialExploreJoinTitle)
                .font(.headline)
                .foregroundStyle(AppTheme.color(for: .primaryText01, theme: theme))
            Text(L10n.socialExploreJoinMessage)
                .font(.subheadline)
                .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
            Button(L10n.socialClaimHandle) {
                viewModel.startJoin()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.color(for: .primaryInteractive01, theme: theme))
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        // primaryUi05 (not primaryUi02): the card sits on the primaryUi01 tab
        // background, and primaryUi02 matches it in the light themes.
        .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.color(for: .primaryUi05, theme: theme)))
        .padding(.horizontal, 16)
    }
}

/// One derived feed item: actor/verb/subject line, kind icon, relative time.
struct FeedItemRow: View {
    @EnvironmentObject var theme: Theme
    let item: FeedItem
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.color(for: .primaryIcon02, theme: theme))
                    .frame(width: 22)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.color(for: .primaryText01, theme: theme))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !item.reviewExcerpt.isEmpty {
                        Text("“" + item.reviewExcerpt + "”")
                            .font(.footnote)
                            .italic()
                            .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    if let eventAt = item.eventAt {
                        Text(eventAt.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var actor: String {
        item.actorDisplayName.isEmpty ? "@" + item.actorHandle : item.actorDisplayName
    }

    private var title: String {
        switch item.kind {
        case .joined:
            return L10n.socialFeedItemJoined(actor)
        case .followedPerson:
            return L10n.socialFeedItemFollowedPerson(actor, "@" + item.targetHandle)
        case .followedShow:
            return L10n.socialFeedItemFollowedShow(actor, item.podcastTitle)
        case .finishedEpisode:
            return L10n.socialFeedItemFinished(actor, item.episodeTitle)
        case .reviewed:
            return L10n.socialFeedItemReviewed(actor, item.podcastTitle)
        case .reacted:
            let emoji = item.reactionKind.map { "\($0.emoji) " } ?? ""
            return emoji + L10n.socialFeedItemReacted(actor, item.episodeTitle)
        case .commented:
            return L10n.socialFeedItemCommented(actor, item.episodeTitle)
        case .publishedList:
            return L10n.socialFeedItemPublishedList(actor, item.listTitle)
        }
    }

    private var icon: String {
        switch item.kind {
        case .joined: return "person.crop.circle.badge.plus"
        case .followedPerson: return "person.2"
        case .followedShow: return "plus.circle"
        case .finishedEpisode: return "checkmark.circle"
        case .reviewed: return "star.bubble"
        case .reacted: return "heart"
        case .commented: return "bubble.left.and.bubble.right"
        case .publishedList: return "list.star"
        }
    }
}

@MainActor
final class SocialFeedViewModel: ObservableObject {
    @Published private(set) var items: [FeedItem] = []
    @Published private(set) var trending: [TrendingPodcast] = []
    @Published private(set) var isLoading = true
    @Published private(set) var isJoined: Bool

    private var fixtureLoaded = false
    private var lastLoadedJoined: Bool?
    private static let pageSize = 30

    init() {
        isJoined = FeatureFlag.socialProfiles.enabled && SocialIdentityStore.isJoined
    }

    /// Fixture initializer for snapshots/previews; load() then no-ops.
    init(fixture: [FeedItem], isJoined: Bool = true, trending: [TrendingPodcast] = []) {
        items = fixture
        self.trending = trending
        self.isJoined = isJoined
        isLoading = false
        fixtureLoaded = true
        lastLoadedJoined = isJoined
    }

    func load() async {
        guard !fixtureLoaded else { return }
        isJoined = FeatureFlag.socialProfiles.enabled && SocialIdentityStore.isJoined
        lastLoadedJoined = isJoined
        guard isJoined else {
            isLoading = false
            return
        }
        Analytics.track(.socialFeedShown)
        items = await ApiServerHandler.shared.fetchFeed(limit: Self.pageSize) ?? []
        trending = await ApiServerHandler.shared.fetchTrendingWithFriends() ?? []
        isLoading = false
    }

    /// Re-loads when the joined state changed since the last load (e.g. the
    /// user joined from the card and navigated back to Explore).
    func refreshIfStale() async {
        guard !fixtureLoaded else { return }
        let joinedNow = FeatureFlag.socialProfiles.enabled && SocialIdentityStore.isJoined
        if joinedNow != lastLoadedJoined {
            isLoading = true
            lastLoadedJoined = nil
            await load()
        }
    }

    func startJoin() {
        guard let root = SceneHelper.rootViewController() else { return }
        var top: UIViewController = root
        while let presented = top.presentedViewController { top = presented }
        SocialCoordinator.presentJoinFlow(from: top, navigationController: nil)
    }

    func openTrending(_ podcast: TrendingPodcast) {
        Analytics.track(.socialTrendingTapped)
        NavigationManager.sharedManager.navigateTo(NavigationManager.podcastPageKey,
                                                   data: [NavigationManager.podcastKey: podcast.podcastUuid])
    }

    /// Per-kind navigation: people items open profiles, show items open the
    /// podcast page, episode items open the episode card.
    func open(_ item: FeedItem) {
        Analytics.track(.socialFeedItemTapped)
        switch item.kind {
        case .joined:
            SocialCoordinator.openPublicProfile(handle: item.actorHandle)
        case .followedPerson:
            SocialCoordinator.openPublicProfile(handle: item.targetHandle.isEmpty ? item.actorHandle : item.targetHandle)
        case .followedShow, .reviewed:
            guard !item.podcastUuid.isEmpty else { return }
            NavigationManager.sharedManager.navigateTo(NavigationManager.podcastPageKey,
                                                       data: [NavigationManager.podcastKey: item.podcastUuid])
        case .finishedEpisode, .reacted, .commented:
            guard !item.episodeUuid.isEmpty else { return }
            NavigationManager.sharedManager.navigateTo(NavigationManager.episodePageKey,
                                                       data: [NavigationManager.episodeUuidKey: item.episodeUuid,
                                                              NavigationManager.podcastKey: item.podcastUuid])
        case .publishedList:
            guard item.listId > 0 else { return }
            SocialCoordinator.openSharedList(id: item.listId)
        }
    }
}
