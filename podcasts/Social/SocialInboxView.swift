import SwiftUI
import PocketCastsServer
import PocketCastsUtils

/// The Inbox (docs/Social.md): everything addressed to you — pending follow
/// requests (Slice 5), replies to your comments (Slice 6, watermark-based
/// unread), and Shared Items friends sent (Slice 4, marked read on appear,
/// swipe to delete, opens at the carried timestamp). React on shared items is
/// deferred until senders can see reactions (roadmap amendment).
struct SocialInboxView: View {
    @EnvironmentObject var theme: Theme
    @StateObject var viewModel: SocialInboxViewModel

    var body: some View {
        List {
            if !viewModel.requests.isEmpty {
                Section(header: Text(L10n.socialFollowRequestsTitle)) {
                    ForEach(viewModel.requests) { entry in
                        requestRow(entry)
                    }
                }
            }

            if !viewModel.replies.isEmpty {
                Section(header: Text(L10n.socialInboxRepliesTitle)) {
                    ForEach(viewModel.replies) { reply in
                        Button {
                            viewModel.open(reply)
                        } label: {
                            replyRow(reply)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if viewModel.items.isEmpty, !viewModel.isLoading {
                Section {
                    Text(L10n.socialInboxEmpty)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                }
            } else {
                ForEach(viewModel.items) { item in
                    Button {
                        viewModel.open(item)
                    } label: {
                        itemRow(item)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    Task { await viewModel.delete(at: offsets) }
                }
                if viewModel.canLoadMore {
                    Button(L10n.socialReviewsLoadMore) {
                        Task { await viewModel.loadMore() }
                    }
                }
            }
        }
        .navigationTitle(L10n.socialInboxTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    private func requestRow(_ entry: FollowEntry) -> some View {
        HStack(spacing: 10) {
            Button {
                SocialCoordinator.openPublicProfile(handle: entry.handle)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName.isEmpty ? "@" + entry.handle : entry.displayName)
                        .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                    Text("@" + entry.handle)
                        .font(.footnote)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button(L10n.socialFollowAccept) {
                Task { await viewModel.respond(to: entry, accept: true) }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderedProminent)
            Button(L10n.socialFollowDecline) {
                Task { await viewModel.respond(to: entry, accept: false) }
            }
            .font(.subheadline)
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 2)
    }

    private func replyRow(_ reply: SocialComment) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.socialInboxReplyFrom(reply.displayName, "@" + reply.handle))
                .font(.footnote)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            Text("\u{201C}" + reply.text + "\u{201D}")
                .font(.subheadline)
                .lineLimit(2)
            if !reply.episodeTitle.isEmpty {
                Text(reply.episodeTitle)
                    .font(.footnote)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func itemRow(_ item: SharedItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(item.read ? Color.clear : AppTheme.color(for: .primaryInteractive01, theme: theme))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.socialInboxSentBy(item.senderDisplayName, "@" + item.senderHandle))
                    .font(.footnote)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                // A show recommendation (Slice 15) carries no episode: the
                // podcast title leads and the row opens the podcast page.
                if item.episodeUuid.isEmpty {
                    Label(item.podcastTitle.isEmpty ? item.podcastUuid : item.podcastTitle, systemImage: "mic")
                        .font(.subheadline.bold())
                        .lineLimit(2)
                } else {
                    Text(item.episodeTitle.isEmpty ? item.episodeUuid : item.episodeTitle)
                        .font(.subheadline.bold())
                        .lineLimit(2)
                }
                if !item.podcastTitle.isEmpty, !item.episodeUuid.isEmpty {
                    Text(item.podcastTitle)
                        .font(.footnote)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                        .lineLimit(1)
                }
                if !item.note.isEmpty {
                    Text("“" + item.note + "”")
                        .font(.subheadline)
                        .italic()
                }
                if let createdAt = item.createdAt {
                    Text(createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                }
            }
        }
        .padding(.vertical, 4)
    }
}

@MainActor
final class SocialInboxViewModel: ObservableObject {
    @Published private(set) var items: [SharedItem] = []
    @Published private(set) var requests: [FollowEntry] = []
    @Published private(set) var replies: [SocialComment] = []
    @Published private(set) var total = 0
    @Published private(set) var isLoading = true

    private var fixtureLoaded = false
    private static let pageSize = 50

    init() {}

    /// Fixture initializer for snapshots/previews; load() then no-ops.
    init(fixture: SocialInboxPage, requests: [FollowEntry] = [], replies: [SocialComment] = []) {
        items = fixture.items
        self.requests = requests
        self.replies = replies
        total = fixture.total
        isLoading = false
        fixtureLoaded = true
    }

    var canLoadMore: Bool { items.count < total }

    func load() async {
        guard !fixtureLoaded else { return }
        Analytics.track(.socialInboxOpened)
        requests = await ApiServerHandler.shared.fetchFollowRequests()?.entries ?? []
        if let repliesPage = await ApiServerHandler.shared.fetchInboxReplies() {
            replies = repliesPage.replies
            if repliesPage.unread > 0 {
                Analytics.track(.socialInboxRepliesOpened)
                await ApiServerHandler.shared.markInboxRepliesSeen()
            }
        }
        guard let page = await ApiServerHandler.shared.fetchInbox() else {
            isLoading = false
            return
        }
        items = page.items
        total = page.total
        isLoading = false
        SocialInboxBadge.unreadCount = 0

        // Everything shown is now seen; mark unread items read server-side.
        let unreadIds = page.items.filter { !$0.read }.map(\.id)
        if !unreadIds.isEmpty {
            _ = await ApiServerHandler.shared.markInboxRead(ids: unreadIds)
        }
    }

    /// Opens the replied-to conversation at the episode.
    func open(_ reply: SocialComment) {
        NavigationManager.sharedManager.navigateTo(NavigationManager.episodePageKey,
                                                   data: [NavigationManager.episodeUuidKey: reply.episodeUuid,
                                                          NavigationManager.podcastKey: reply.podcastUuid])
    }

    /// Accept makes the requester an active follower (they may now see
    /// Followers-tier fields); decline removes the pending row server-side.
    func respond(to entry: FollowEntry, accept: Bool) async {
        guard await ApiServerHandler.shared.respondToFollowRequest(requesterHandle: entry.handle, accept: accept) else { return }
        if accept {
            Analytics.track(.socialFollowApproved)
        }
        requests.removeAll { $0.handle == entry.handle }
    }

    func loadMore() async {
        guard let page = await ApiServerHandler.shared.fetchInbox(limit: Self.pageSize, offset: items.count) else { return }
        items.append(contentsOf: page.items)
        total = page.total
    }

    func open(_ item: SharedItem) {
        Analytics.track(.socialInboxItemOpened)
        if item.episodeUuid.isEmpty {
            // PodcastInfo, not a bare uuid: the String branch of the podcast
            // navigation silently no-ops when the show isn't in the local
            // database, and a recommended show usually isn't.
            var info = PodcastInfo()
            info.uuid = item.podcastUuid
            info.title = item.podcastTitle
            NavigationManager.sharedManager.navigateTo(NavigationManager.podcastPageKey,
                                                       data: [NavigationManager.podcastKey: info])
            return
        }
        let timestamp: TimeInterval? = item.timestampSeconds > 0 ? TimeInterval(item.timestampSeconds) : nil
        NavigationManager.sharedManager.navigateTo(NavigationManager.episodePageKey,
                                                   data: [NavigationManager.episodeUuidKey: item.episodeUuid,
                                                          NavigationManager.podcastKey: item.podcastUuid,
                                                          NavigationManager.episodeTimestamp: timestamp as Any])
    }

    func delete(at offsets: IndexSet) async {
        let doomed = offsets.map { items[$0] }
        items.remove(atOffsets: offsets)
        total = max(0, total - doomed.count)
        for item in doomed {
            _ = await ApiServerHandler.shared.deleteInboxItem(id: item.id)
        }
    }
}

/// Lightweight cache of the unread count so the Profile-tab row can badge
/// without a fetch; refreshed whenever the inbox loads.
enum SocialInboxBadge {
    private static let key = "SocialInboxUnreadCount"

    static var unreadCount: Int {
        get { UserDefaults.standard.integer(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Refreshes the cached count from the server (fire-and-forget).
    static func refresh() {
        guard FeatureFlag.socialProfiles.enabled, SocialIdentityStore.isJoined else { return }
        Task { @MainActor in
            if let page = await ApiServerHandler.shared.fetchInbox(limit: 1) {
                unreadCount = page.unread
            }
        }
    }
}
