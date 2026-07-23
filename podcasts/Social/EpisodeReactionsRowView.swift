import SwiftUI
import PocketCastsServer
import PocketCastsUtils

/// The episode reactions row (Slice 3, docs/Social.md): the fixed emoji set
/// with aggregate counts; the caller's own reaction highlighted. Reacting is
/// account-level (no Join needed) and listen-gated to ≥25% of the episode
/// played. Counts-only display — attribution waits for Phase-2 feeds.
struct EpisodeReactionsRowView: View {
    @EnvironmentObject var theme: Theme
    @ObservedObject var viewModel: EpisodeReactionsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.socialReactionsTitle)
                .font(.subheadline.bold())
            HStack(spacing: 8) {
                ForEach(ReactionKind.allCases) { kind in
                    chip(kind)
                }
            }
            if !viewModel.canReact {
                Text(L10n.socialReactionsGateHint)
                    .font(.caption)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.color(for: .primaryUi02Active, theme: theme))
        .cornerRadius(8)
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 14)
        .task { await viewModel.load() }
    }

    private func chip(_ kind: ReactionKind) -> some View {
        let count = viewModel.reactions.counts[kind] ?? 0
        let isMine = viewModel.reactions.yourReaction == kind
        return Button {
            Task { await viewModel.tap(kind) }
        } label: {
            HStack(spacing: 4) {
                Text(kind.emoji)
                if count > 0 {
                    Text("\(count)")
                        .font(.footnote.monospacedDigit())
                        .foregroundColor(AppTheme.color(for: isMine ? .primaryInteractive02 : .primaryText02, theme: theme))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isMine
                ? AppTheme.color(for: .primaryInteractive01, theme: theme)
                : AppTheme.color(for: .primaryUi05, theme: theme).opacity(0.35))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canReact)
        .opacity(viewModel.canReact ? 1 : 0.5)
        .accessibilityLabel("\(kind.emoji) \(count)")
    }
}

@MainActor
final class EpisodeReactionsViewModel: ObservableObject {
    typealias FetchReactions = @MainActor (String) async -> EpisodeReactions?
    typealias SetReaction = @MainActor (String, ReactionKind?) async -> Bool

    let episodeUuid: String
    let canReact: Bool

    @Published private(set) var reactions = EpisodeReactions(counts: [:], yourReaction: nil)
    private var loaded = false
    private var isUpdating = false
    /// The last server-confirmed state — the revert target when a write and
    /// its recovery fetch both fail.
    private var confirmedReactions = EpisodeReactions(counts: [:], yourReaction: nil)
    private var pendingKind: ReactionKind?
    private var hasPendingWrite = false
    private let fetchReactions: FetchReactions
    private let setReaction: SetReaction

    /// `fixture` preloads state for snapshots/previews; load() then no-ops.
    init(episodeUuid: String,
         canReact: Bool,
         fixture: EpisodeReactions? = nil,
         fetchReactions: @escaping FetchReactions = { await ApiServerHandler.shared.fetchReactions(episodeUuid: $0) },
         setReaction: @escaping SetReaction = { await ApiServerHandler.shared.setReaction(episodeUuid: $0, kind: $1) }) {
        self.episodeUuid = episodeUuid
        self.canReact = canReact
        self.fetchReactions = fetchReactions
        self.setReaction = setReaction
        if let fixture {
            reactions = fixture
            confirmedReactions = fixture
            loaded = true
        }
    }

    func load() async {
        guard !loaded else { return }
        if let fetched = await fetchReactions(episodeUuid) {
            reactions = fetched
            confirmedReactions = fetched
        }
        loaded = true
    }

    /// Tap semantics: same emoji again clears; a different one switches.
    /// A tap while a mutation is in flight isn't dropped: the latest intent is
    /// remembered and written once the in-flight mutation completes (the
    /// single-writer pattern of SocialNotificationSettingsViewModel).
    func tap(_ kind: ReactionKind) async {
        guard canReact else { return }

        let newKind: ReactionKind? = reactions.yourReaction == kind ? nil : kind

        // Optimistic local update; the server row is the source of truth.
        var counts = reactions.counts
        if let old = reactions.yourReaction {
            counts[old] = max(0, (counts[old] ?? 1) - 1)
            if counts[old] == 0 { counts.removeValue(forKey: old) }
        }
        if let newKind {
            counts[newKind] = (counts[newKind] ?? 0) + 1
        }
        reactions = EpisodeReactions(counts: counts, yourReaction: newKind)

        Analytics.track(.socialReactionSet)
        pendingKind = newKind
        hasPendingWrite = true
        guard !isUpdating else { return }
        await persistPendingReaction()
    }

    /// Serializes reaction writes: one writer in flight, and any newer desired
    /// kind queued mid-write is sent immediately after it.
    private func persistPendingReaction() async {
        isUpdating = true
        defer { isUpdating = false }

        while hasPendingWrite {
            let requestedKind = pendingKind
            // Snapshot the optimistic state represented by this request before
            // a newer tap can mutate `reactions` while the network call suspends.
            let requestedReactions = reactions
            hasPendingWrite = false

            if await setReaction(episodeUuid, requestedKind) {
                // Every successful write advances the recovery point, even when a
                // newer intent is already queued. A later write + refresh failure
                // must fall back to what the server most recently confirmed.
                confirmedReactions = requestedReactions
                continue
            }
            // A newer intent supersedes the failed write; otherwise resync.
            guard !hasPendingWrite else { continue }
            let refreshed = await fetchReactions(episodeUuid)
            guard !hasPendingWrite else { continue }
            reactions = refreshed ?? confirmedReactions
            confirmedReactions = reactions
        }
    }
}
