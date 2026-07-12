import PocketCastsDataModel
import SwiftUI

/// A shelf of the user's own podcasts, ordered by recently played, shown on
/// the empty search screen so the space between the field and the keyboard is
/// never blank — even before any search history exists. Local data only.
///
/// The podcasts are loaded by the parent (`SearchHistoryView`): this view
/// lives inside a `LazyVStack`, where a zero-size child is never materialized,
/// so it can't bootstrap its own data with `.task`/`.onAppear`.
struct SearchLocalSuggestionsView: View {
    @EnvironmentObject var theme: Theme

    let podcasts: [Podcast]

    var body: some View {
        VStack(spacing: 0) {
            ThemeableListHeader(title: L10n.searchYourPodcasts, actionTitle: nil, action: nil)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(podcasts, id: \.uuid) { podcast in
                        tile(for: podcast)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }

    private func tile(for podcast: Podcast) -> some View {
        Button {
            NavigationManager.sharedManager.navigateTo(NavigationManager.podcastPageKey, data: [NavigationManager.podcastKey: podcast])
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                PodcastImage(uuid: podcast.uuid, size: .grid)
                    .frame(width: 96, height: 96)
                    .cornerRadius(4)
                    .shadow(radius: 3, x: 0, y: 1)

                Text(podcast.title ?? "")
                    .font(style: .footnote, weight: .medium)
                    .foregroundStyle(theme.primaryText01)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(width: 96, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(podcast.title ?? "")
    }
}

struct SearchLocalSuggestionsView_Previews: PreviewProvider {
    static var previews: some View {
        SearchLocalSuggestionsView(podcasts: [])
            .previewWithAllThemes()
    }
}
