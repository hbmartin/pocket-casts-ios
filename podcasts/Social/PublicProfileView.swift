import SwiftUI
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils

/// Another user's Social Profile, fetched by handle. The server has already
/// applied per-field visibility and the viewer's block relationship — a
/// blocked, missing or tombstoned handle all render the same not-found state
/// (docs/SocialModeration.md). Block + report + mute live in the overflow menu
/// (mute shipped with the feed it filters — ADR-0007 amendment fulfilled,
/// Slice 5). Joined viewers get the Follow button; followers may see
/// followers-only fields (server-applied).
struct PublicProfileView: View {
    @EnvironmentObject var theme: Theme
    @StateObject var viewModel: PublicProfileViewModel

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notFound:
                notFoundView
            case .loaded(let profile):
                profileList(profile)
            }
        }
        .navigationTitle("@" + viewModel.handle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if case .loaded(let profile) = viewModel.state {
                ToolbarItem(placement: .topBarTrailing) {
                    overflowMenu(profile)
                }
            }
        }
        .confirmationDialog(L10n.socialReportTitle, isPresented: $viewModel.showingReportPicker, titleVisibility: .visible) {
            ForEach(PublicProfileViewModel.reportReasons, id: \.1) { label, reason in
                Button(label) { Task { await viewModel.report(reason: reason) } }
            }
            Button(L10n.cancel, role: .cancel) {}
        }
        .alert(L10n.socialBlockConfirmTitle, isPresented: $viewModel.showingBlockConfirm) {
            Button(L10n.cancel, role: .cancel) {}
            Button(L10n.socialBlock, role: .destructive) { Task { await viewModel.setBlocked(true) } }
        } message: {
            Text(L10n.socialBlockConfirmMessage)
        }
        .task { await viewModel.load() }
    }

    private var notFoundView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.slash")
                .font(.system(size: 44))
                .foregroundColor(AppTheme.color(for: .primaryIcon02, theme: theme))
            Text(L10n.socialProfileNotFound)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func profileList(_ profile: SocialPublicProfile) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.displayName)
                        .font(.title2.bold())
                    Text("@" + profile.handle)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                    if !profile.bio.isEmpty {
                        Text(profile.bio)
                            .font(.subheadline)
                    }
                    HStack(spacing: 4) {
                        Text("\(profile.followerCount)").bold()
                        Text(L10n.socialFollowersTitle)
                        Text("·")
                        Text("\(profile.followingCount)").bold()
                        Text(L10n.socialFollowingTitle)
                    }
                    .font(.footnote)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                    if viewModel.isBlocked {
                        Label(L10n.socialBlockedLabel, systemImage: "hand.raised.fill")
                            .font(.footnote)
                            .foregroundColor(AppTheme.color(for: .support05, theme: theme))
                    }
                    if viewModel.showsFollowButton {
                        followButton
                    }
                }
                .padding(.vertical, 4)
            }

            if let stats = profile.stats {
                Section(header: Text(L10n.socialSectionStats)) {
                    HStack {
                        Text(L10n.socialStatsHoursListened)
                        Spacer()
                        Text("\(stats.timeListenedSeconds / 3600)")
                            .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                    }
                    if let since = stats.listeningSince {
                        HStack {
                            Text(L10n.socialStatsListeningSince)
                            Spacer()
                            Text(since.formatted(.dateTime.month(.wide).year()))
                                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                        }
                    }
                }
            }

            podcastSection(L10n.socialSectionTopPodcasts, podcasts: profile.topPodcasts)
            podcastSection(L10n.socialSectionFollowedShows, podcasts: profile.followedShows)

            if !profile.lists.isEmpty {
                Section(header: Text(L10n.socialSectionLists)) {
                    ForEach(profile.lists) { list in
                        Button {
                            SocialCoordinator.openSharedList(id: list.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(list.title)
                                    .lineLimit(1)
                                    .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                                Text(list.entryCount == 1 ? L10n.socialListEpisodeCountSingular : L10n.socialListEpisodeCount(list.entryCount))
                                    .font(.footnote)
                                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                            }
                        }
                    }
                }
            }

            if !profile.recentlyPlayed.isEmpty {
                Section(header: Text(L10n.socialSectionRecentlyPlayed)) {
                    ForEach(profile.recentlyPlayed) { episode in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(episode.title.isEmpty ? episode.uuid : episode.title)
                                .lineLimit(1)
                            if let playedAt = episode.playedAt {
                                Text(playedAt.formatted(.relative(presentation: .named)))
                                    .font(.footnote)
                                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                            }
                        }
                    }
                }
            }
        }
    }

    /// Follow / Requested / Following. Follow acts immediately; the other two
    /// states confirm before severing (a declined request can't be re-secretly
    /// re-requested without the owner noticing, and unfollow loses feed items).
    private var followButton: some View {
        Button {
            if viewModel.followState == .none {
                Task { await viewModel.follow() }
            } else {
                viewModel.showingUnfollowConfirm = true
            }
        } label: {
            HStack {
                if viewModel.isUpdatingFollow {
                    ProgressView()
                } else {
                    Text(followButtonTitle)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.color(for: viewModel.followState == .none ? .primaryInteractive01 : .primaryUi05, theme: theme))
            )
            .foregroundColor(AppTheme.color(for: viewModel.followState == .none ? .primaryInteractive02 : .primaryText01, theme: theme))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .confirmationDialog(L10n.socialUnfollow, isPresented: $viewModel.showingUnfollowConfirm, titleVisibility: .hidden) {
            Button(L10n.socialUnfollow, role: .destructive) { Task { await viewModel.unfollow() } }
            Button(L10n.cancel, role: .cancel) {}
        }
    }

    private var followButtonTitle: String {
        switch viewModel.followState {
        case .none: return L10n.socialFollow
        case .pending: return L10n.socialFollowRequested
        case .active: return L10n.socialFollowing
        }
    }

    @ViewBuilder
    private func podcastSection(_ header: String, podcasts: [SocialProfilePodcast]) -> some View {
        if !podcasts.isEmpty {
            Section(header: Text(header)) {
                ForEach(podcasts) { podcast in
                    Button {
                        viewModel.openPodcast(podcast)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(podcast.title.isEmpty ? podcast.uuid : podcast.title)
                                .lineLimit(1)
                                .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                            if !podcast.author.isEmpty {
                                Text(podcast.author)
                                    .font(.footnote)
                                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                            }
                        }
                    }
                }
            }
        }
    }

    private func overflowMenu(_ profile: SocialPublicProfile) -> some View {
        Menu {
            if viewModel.isMuted {
                Button {
                    Task { await viewModel.setMuted(false) }
                } label: {
                    Label(L10n.socialUnmute, systemImage: "speaker.wave.2")
                }
            } else {
                Button {
                    Task { await viewModel.setMuted(true) }
                } label: {
                    Label(L10n.socialMute, systemImage: "speaker.slash")
                }
            }
            if viewModel.isBlocked {
                Button {
                    Task { await viewModel.setBlocked(false) }
                } label: {
                    Label(L10n.socialUnblock, systemImage: "hand.raised.slash")
                }
            } else {
                Button(role: .destructive) {
                    viewModel.showingBlockConfirm = true
                } label: {
                    Label(L10n.socialBlock, systemImage: "hand.raised")
                }
            }
            Button(role: .destructive) {
                viewModel.showingReportPicker = true
            } label: {
                Label(L10n.socialReport, systemImage: "flag")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
}

@MainActor
final class PublicProfileViewModel: ObservableObject {
    enum State { case loading, notFound, loaded(SocialPublicProfile) }

    static let reportReasons: [(String, SocialReportReason)] = [
        (L10n.socialReportSpam, .spam),
        (L10n.socialReportHarassment, .harassment),
        (L10n.socialReportHate, .hate),
        (L10n.socialReportSexual, .sexual),
        (L10n.socialReportImpersonation, .impersonation),
        (L10n.socialReportOther, .other),
    ]

    let handle: String
    @Published private(set) var state: State = .loading
    @Published private(set) var isBlocked = false
    @Published private(set) var isMuted = false
    @Published private(set) var followState: FollowState = .none
    @Published private(set) var isUpdatingFollow = false
    @Published var showingReportPicker = false
    @Published var showingBlockConfirm = false
    @Published var showingUnfollowConfirm = false

    /// `fixture` preloads a state (snapshot tests/previews); `load()` then no-ops.
    init(handle: String, fixture: State? = nil) {
        self.handle = handle.lowercased()
        if let fixture {
            state = fixture
            if case .loaded(let profile) = fixture {
                followState = profile.yourFollowState
            }
        }
    }

    /// Follow button shows for joined viewers on profiles other than their own
    /// (the server rejects self-follow anyway; don't render a dead control).
    var showsFollowButton: Bool {
        guard SocialIdentityStore.isJoined, !isBlocked else { return false }
        guard case .loaded(let profile) = state else { return false }
        return profile.userId != SocialIdentityStore.cachedProfile?.userId
    }

    func load() async {
        guard case .loading = state else { return }
        guard let profile = await ApiServerHandler.shared.fetchPublicProfile(handle: handle) else {
            state = .notFound
            return
        }
        isBlocked = DataManager.sharedManager.socialGraph.isBlocked(profile.userId)
        isMuted = DataManager.sharedManager.socialGraph.isMuted(profile.userId)
        followState = profile.yourFollowState
        state = .loaded(profile)
    }

    /// Open accounts return .active immediately; approval-gated ones .pending.
    func follow() async {
        isUpdatingFollow = true
        if let newState = await ApiServerHandler.shared.follow(handle: handle) {
            followState = newState
            Analytics.track(.socialFollowed)
        }
        isUpdatingFollow = false
    }

    /// Also cancels a pending request (same endpoint server-side).
    func unfollow() async {
        isUpdatingFollow = true
        if await ApiServerHandler.shared.unfollow(handle: handle) != nil {
            followState = .none
        }
        isUpdatingFollow = false
    }

    /// Mute = one-way hide from the feed; the muted person is never notified
    /// (docs/SocialModeration.md). Mirrored locally, server authoritative.
    func setMuted(_ muted: Bool) async {
        guard case .loaded(let profile) = state else { return }
        if muted {
            DataManager.sharedManager.socialGraph.add(targetUserId: profile.userId, handle: profile.handle, type: .mute)
            Analytics.track(.socialProfileMuted)
        } else {
            DataManager.sharedManager.socialGraph.remove(targetUserId: profile.userId, type: .mute)
        }
        isMuted = muted
        _ = await ApiServerHandler.shared.setMuted(muted, targetUserId: profile.userId)
    }

    /// Block = mutual invisibility: mirror locally for instant filtering, tell
    /// the server (authoritative), and reload — a fresh block turns this
    /// profile into the not-found shape on the next read.
    func setBlocked(_ blocked: Bool) async {
        guard case .loaded(let profile) = state else { return }
        if blocked {
            DataManager.sharedManager.socialGraph.add(targetUserId: profile.userId, handle: profile.handle, type: .block)
            Analytics.track(.socialProfileBlocked)
        } else {
            DataManager.sharedManager.socialGraph.remove(targetUserId: profile.userId, type: .block)
        }
        isBlocked = blocked
        _ = await ApiServerHandler.shared.setBlocked(blocked, targetUserId: profile.userId)
    }

    func report(reason: SocialReportReason) async {
        guard case .loaded(let profile) = state else { return }
        Analytics.track(.socialProfileReported)
        _ = await ApiServerHandler.shared.reportUser(targetUserId: profile.userId, reason: reason)
    }

    /// Opens a section podcast in the app's podcast page.
    func openPodcast(_ podcast: SocialProfilePodcast) {
        NavigationManager.sharedManager.navigateTo(NavigationManager.podcastPageKey,
                                                   data: [NavigationManager.podcastKey: podcast.uuid])
    }
}
