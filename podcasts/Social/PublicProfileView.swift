import SwiftUI
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils

/// Another user's Social Profile, fetched by handle. The server has already
/// applied per-field visibility and the viewer's block relationship — a
/// blocked, missing or tombstoned handle all render the same not-found state
/// (docs/SocialModeration.md). Block + report live in the overflow menu; the
/// mute affordance deliberately waits for the first feed surface (ADR-0007,
/// 2026-07-16 amendment).
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
                    if viewModel.isBlocked {
                        Label(L10n.socialBlockedLabel, systemImage: "hand.raised.fill")
                            .font(.footnote)
                            .foregroundColor(AppTheme.color(for: .support05, theme: theme))
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
    @Published var showingReportPicker = false
    @Published var showingBlockConfirm = false

    init(handle: String) {
        self.handle = handle.lowercased()
    }

    func load() async {
        guard let profile = await ApiServerHandler.shared.fetchPublicProfile(handle: handle) else {
            state = .notFound
            return
        }
        isBlocked = DataManager.sharedManager.socialGraph.isBlocked(profile.userId)
        state = .loaded(profile)
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
