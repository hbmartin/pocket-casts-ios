import SwiftUI
import PocketCastsServer
import PocketCastsUtils

struct SearchResultsListView: View {
    enum DisplayMode: String, AnalyticsDescribable, CaseIterable, Identifiable {
        case allResults
        case podcasts
        case episodes
        case transcripts

        var analyticsDescription: String {
            rawValue
        }

        var id: String {
            rawValue
        }

        var localizedDescription: String {
            switch self {
                case .allResults:
                    return L10n.allResults
                case .podcasts:
                    return L10n.podcastsPlural
                case .episodes:
                    return L10n.episodes
                case .transcripts:
                    return L10n.searchTranscriptsPill
            }
        }

        /// The pills offered by the results filter: `.transcripts` only exists
        /// while the library transcript search flag is on.
        static var availableCases: [DisplayMode] {
            allCases.filter { $0 != .transcripts || FeatureFlag.transcriptSearch.enabled }
        }
    }

    @EnvironmentObject var theme: Theme
    @EnvironmentObject var searchAnalyticsHelper: SearchAnalyticsHelper
    @EnvironmentObject var searchResults: SearchResultsModel
    @EnvironmentObject var searchHistory: SearchHistoryModel

    var displayMode: DisplayMode

    var body: some View {
        VStack(spacing: 0) {
            ThemedDivider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    switch displayMode {
                    case .podcasts:
                        ForEach(searchResults.podcasts, id: \.self) { podcast in

                            SearchResultCell(episode: nil, result: podcast)
                        }

                    case .episodes:
                        ForEach(searchResults.episodes, id: \.self) { episode in

                            SearchResultCell(episode: episode, result: nil)
                        }
                    case .allResults:
                        ForEach(searchResults.podcasts, id: \.self) { podcast in
                            SearchResultCell(episode: nil, result: podcast)
                        }
                        ForEach(searchResults.episodes, id: \.self) { episode in
                            SearchResultCell(episode: episode, result: nil)
                        }
                    case .transcripts:
                        ForEach(Array(searchResults.transcriptHits.enumerated()), id: \.element) { position, hit in
                            TranscriptSearchResultRow(display: hit, position: position)
                                .padding(.horizontal, 16)
                        }
                    }
                    if displayMode == .podcasts && searchResults.isSearchingForPodcasts || displayMode == .episodes && searchResults.isSearchingForEpisodes {
                        ProgressView()
                        .frame(maxWidth: .infinity)
                        .tint(AppTheme.loadingActivityColor().color)
                        .padding(10)
                    }
                }
            }
            .navigationBarTitle(Text(displayMode == .podcasts ? L10n.discoverAllPodcasts : L10n.discoverAllEpisodes))
        }
        .ignoresSafeArea(.keyboard)
        .onAppear {
            searchAnalyticsHelper.trackListShown(displayMode)
        }
        .applyDefaultThemeOptions()
    }
}

struct PodcastResultsView_Previews: PreviewProvider {
    static var previews: some View {
        SearchResultsListView(displayMode: .podcasts)
    }
}
