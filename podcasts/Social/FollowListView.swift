import SwiftUI
import PocketCastsServer

/// The owner's followers or following list (Slice 5, docs/Social.md). The
/// backend only serves the caller's own lists — other profiles show counts
/// only — so this is reached from the own-profile screen. Rows open the
/// person's public profile.
struct FollowListView: View {
    @EnvironmentObject var theme: Theme
    @StateObject var viewModel: FollowListViewModel

    var body: some View {
        List {
            if viewModel.entries.isEmpty, !viewModel.isLoading {
                Section {
                    Text(L10n.socialFollowListEmpty)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                }
            } else {
                ForEach(viewModel.entries) { entry in
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
                }
                if viewModel.canLoadMore {
                    Button(L10n.socialReviewsLoadMore) {
                        Task { await viewModel.loadMore() }
                    }
                }
            }
        }
        .navigationTitle(viewModel.kind == .followers ? L10n.socialFollowersTitle : L10n.socialFollowingTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }
}

@MainActor
final class FollowListViewModel: ObservableObject {
    enum Kind { case followers, following }

    let kind: Kind
    @Published private(set) var entries: [FollowEntry] = []
    @Published private(set) var total = 0
    @Published private(set) var isLoading = true

    private var fixtureLoaded = false
    private static let pageSize = 100

    init(kind: Kind) {
        self.kind = kind
    }

    /// Fixture initializer for snapshots/previews; load() then no-ops.
    init(kind: Kind, fixture: FollowList) {
        self.kind = kind
        entries = fixture.entries
        total = fixture.total
        isLoading = false
        fixtureLoaded = true
    }

    var canLoadMore: Bool { entries.count < total }

    func load() async {
        guard !fixtureLoaded else { return }
        if let list = await fetch(offset: 0) {
            entries = list.entries
            total = list.total
        }
        isLoading = false
    }

    func loadMore() async {
        guard let list = await fetch(offset: entries.count) else { return }
        entries.append(contentsOf: list.entries)
        total = list.total
    }

    private func fetch(offset: Int) async -> FollowList? {
        switch kind {
        case .followers:
            return await ApiServerHandler.shared.fetchFollowers(limit: Self.pageSize, offset: offset)
        case .following:
            return await ApiServerHandler.shared.fetchFollowing(limit: Self.pageSize, offset: offset)
        }
    }
}
