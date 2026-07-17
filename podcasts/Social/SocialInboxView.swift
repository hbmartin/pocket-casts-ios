import SwiftUI
import PocketCastsServer
import PocketCastsUtils

/// The shared-item inbox (Slice 4, docs/Social.md): items friends sent you,
/// newest first. Marked read on appear; swipe to delete; tapping opens the
/// episode at the carried timestamp. React is deferred until senders can see
/// reactions (roadmap amendment).
struct SocialInboxView: View {
    @EnvironmentObject var theme: Theme
    @StateObject var viewModel: SocialInboxViewModel

    var body: some View {
        List {
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
                Text(item.episodeTitle.isEmpty ? item.episodeUuid : item.episodeTitle)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                if !item.podcastTitle.isEmpty {
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
    @Published private(set) var total = 0
    @Published private(set) var isLoading = true

    private var fixtureLoaded = false
    private static let pageSize = 50

    init() {}

    /// Fixture initializer for snapshots/previews; load() then no-ops.
    init(fixture: SocialInboxPage) {
        items = fixture.items
        total = fixture.total
        isLoading = false
        fixtureLoaded = true
    }

    var canLoadMore: Bool { items.count < total }

    func load() async {
        guard !fixtureLoaded else { return }
        Analytics.track(.socialInboxOpened)
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

    func loadMore() async {
        guard let page = await ApiServerHandler.shared.fetchInbox(limit: Self.pageSize, offset: items.count) else { return }
        items.append(contentsOf: page.items)
        total = page.total
    }

    func open(_ item: SharedItem) {
        Analytics.track(.socialInboxItemOpened)
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
