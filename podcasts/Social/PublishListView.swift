import SwiftUI
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils

/// Publish a playlist as a shared list (Slice 7, ADR-0011). Manual playlists
/// publish in place (the local playlist links to the new server object);
/// custom/smart playlists MATERIALIZE — their current results snapshot into
/// the new shared list (grill decision: materialize-to-share).
struct PublishListView: View {
    @EnvironmentObject var theme: Theme
    @StateObject var viewModel: PublishListViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section(footer: Text(viewModel.isMaterializing ? L10n.socialListPublishMaterializeNote : L10n.socialListPublishNote)
                    .font(.footnote)) {
                    TextField(L10n.socialListTitlePlaceholder, text: $viewModel.title)
                    TextField(L10n.socialListDescriptionPlaceholder, text: $viewModel.descriptionText)
                }
                Section {
                    Picker(L10n.socialPrivacyTitle, selection: $viewModel.visibility) {
                        ForEach(SocialVisibility.allCases, id: \.self) { tier in
                            Text(tier.localizedName).tag(tier)
                        }
                    }
                    .pickerStyle(.menu)
                }
                if let error = viewModel.publishError {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(AppTheme.color(for: .support05, theme: theme))
                    }
                }
            }
            .navigationTitle(L10n.socialListPublishTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isPublishing {
                        ProgressView()
                    } else {
                        Button(L10n.socialListPublishCta) {
                            Task {
                                if await viewModel.publish() {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(viewModel.title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }
}

@MainActor
final class PublishListViewModel: ObservableObject {
    @Published var title: String
    @Published var descriptionText = ""
    @Published var visibility: SocialVisibility = .private
    @Published private(set) var isPublishing = false
    @Published private(set) var publishError: String?

    private let playlist: EpisodeFilter
    let isMaterializing: Bool

    init(playlist: EpisodeFilter) {
        self.playlist = playlist
        title = playlist.playlistName
        // Manual playlists publish in place; query playlists snapshot.
        isMaterializing = !playlist.manual
    }

    func publish() async -> Bool {
        isPublishing = true
        publishError = nil

        let episodes = DataManager.sharedManager.playlistEpisodes(for: playlist, limit: 500)
        let entries = episodes.enumerated().map { index, episode in
            SharedListEntry(episodeUuid: episode.uuid,
                            podcastUuid: episode.parentIdentifier(),
                            episodeTitle: episode.displayableTitle(),
                            podcastTitle: episode.parentPodcast()?.title ?? "",
                            position: index)
        }

        guard let created = await ApiServerHandler.shared.createSharedList(
            title: title.trimmingCharacters(in: .whitespaces),
            description: descriptionText.trimmingCharacters(in: .whitespaces),
            visibility: visibility,
            entries: entries) else {
            publishError = L10n.socialListPublishFailed
            isPublishing = false
            return false
        }

        Analytics.track(.socialListPublished)
        if !isMaterializing {
            // Link the local manual playlist to its server object.
            var updated = playlist
            updated.sharedListId = created.id
            updated.sharedRole = Int32(SharedListRole.owner.rawValue)
            _ = DataManager.sharedManager.save(playlist: updated)
        }
        isPublishing = false
        return true
    }
}
