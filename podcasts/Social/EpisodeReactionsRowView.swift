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
    let episodeUuid: String
    let canReact: Bool

    @Published private(set) var reactions = EpisodeReactions(counts: [:], yourReaction: nil)
    private var loaded = false

    /// `fixture` preloads state for snapshots/previews; load() then no-ops.
    init(episodeUuid: String, canReact: Bool, fixture: EpisodeReactions? = nil) {
        self.episodeUuid = episodeUuid
        self.canReact = canReact
        if let fixture {
            reactions = fixture
            loaded = true
        }
    }

    func load() async {
        guard !loaded else { return }
        if let fetched = await ApiServerHandler.shared.fetchReactions(episodeUuid: episodeUuid) {
            reactions = fetched
        }
        loaded = true
    }

    /// Tap semantics: same emoji again clears; a different one switches.
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
        let ok = await ApiServerHandler.shared.setReaction(episodeUuid: episodeUuid, kind: newKind)
        if !ok, let fetched = await ApiServerHandler.shared.fetchReactions(episodeUuid: episodeUuid) {
            reactions = fetched // roll back to server truth on failure
        }
    }
}
