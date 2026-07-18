import SwiftUI
import PocketCastsServer
import PocketCastsUtils

/// The episode-card entry into the comment tree (Slice 6): a count row that
/// opens EpisodeCommentsView. Self-tallies lazily; renders even at zero so
/// discussion is discoverable.
struct EpisodeCommentsRowView: View {
    @EnvironmentObject var theme: Theme
    @StateObject var viewModel: EpisodeCommentsRowViewModel

    var body: some View {
        Button {
            viewModel.open()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .foregroundStyle(AppTheme.color(for: .primaryIcon02, theme: theme))
                Text(viewModel.count.map { L10n.socialCommentsRow($0) } ?? L10n.socialCommentsRowUntallied)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.color(for: .primaryText01, theme: theme))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.color(for: .primaryIcon02, theme: theme))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task { await viewModel.tally() }
    }
}

@MainActor
final class EpisodeCommentsRowViewModel: ObservableObject {
    @Published private(set) var count: Int?

    let episodeUuid: String
    let podcastUuid: String
    let episodeTitle: String
    let podcastTitle: String
    let canSeed: Bool
    var onOpen: ((EpisodeCommentsViewModel) -> Void)?

    private var fixtureLoaded = false

    init(episodeUuid: String, podcastUuid: String, episodeTitle: String, podcastTitle: String, canSeed: Bool) {
        self.episodeUuid = episodeUuid
        self.podcastUuid = podcastUuid
        self.episodeTitle = episodeTitle
        self.podcastTitle = podcastTitle
        self.canSeed = canSeed
    }

    /// Fixture initializer for snapshots/previews; tally() then no-ops.
    init(fixtureCount: Int?) {
        episodeUuid = "fixture"
        podcastUuid = ""
        episodeTitle = ""
        podcastTitle = ""
        canSeed = true
        count = fixtureCount
        fixtureLoaded = true
    }

    func tally() async {
        guard !fixtureLoaded, count == nil else { return }
        if let page = await ApiServerHandler.shared.fetchEpisodeComments(episodeUuid: episodeUuid, limit: 1) {
            count = page.total
        }
    }

    func open() {
        onOpen?(EpisodeCommentsViewModel(episodeUuid: episodeUuid, podcastUuid: podcastUuid,
                                         episodeTitle: episodeTitle, podcastTitle: podcastTitle,
                                         canSeed: canSeed))
    }
}
