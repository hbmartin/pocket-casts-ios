import Foundation
import SwiftUI
import PocketCastsUtils

@MainActor
protocol SearchResultsDelegate {
    func clearSearch()
    func performLocalSearch(searchTerm: String)
    func performSearch(searchTerm: String, triggeredByTimer: Bool, completion: @escaping (() -> Void))
}

extension SearchResultsDelegate {
    func performRemoteSearch(searchTerm: String, completion: @escaping (() -> Void)) {}
    func performSearch(searchTerm: String, triggeredByTimer: Bool, completion: @escaping (() -> Void)) {}
}

class SearchResultsViewController: UIHostingController<AnyView> {
    private let displaySearch = SearchVisibilityModel()
    private let searchHistoryModel = SearchHistoryModel.shared
    private let searchResults: SearchResultsModel
    private let searchAnalyticsHelper: SearchAnalyticsHelper

    init(source: AnalyticsSource, showLocalResults: Bool = false) {
        searchAnalyticsHelper = SearchAnalyticsHelper(source: source)
        self.searchResults = SearchResultsModel(analyticsHelper: searchAnalyticsHelper, showLocalResults: showLocalResults)
        super.init(rootView: AnyView(
            SearchView()
            .setupDefaultEnvironment()
            .environmentObject(searchAnalyticsHelper)
            .environmentObject(searchResults)
            .environmentObject(searchHistoryModel)
            .environmentObject(displaySearch))
        )
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Programmatic entry point for searches launched from outside the search
    /// bar (e.g. a person chip on the episode-detail credits card). Mirrors the
    /// search-history cell flow: shows the results, runs the local + remote
    /// searches, records history, and hands the term to the visible search bar.
    func startExternalSearch(term: String) {
        let term = term.trim()
        guard !term.isEmpty else { return }

        displaySearch.isSearching = true
        if searchResults.showLocalResults {
            searchResults.searchLocally(term: term)
        }
        searchResults.search(term: term)
        searchHistoryModel.add(searchTerm: term)
        NotificationCenter.postOnMainThread(PodcastSearchRequested(term: term))
    }

    func searchShown() {
        searchAnalyticsHelper.trackShown()
    }

    func searchDismissed() {
        searchAnalyticsHelper.trackDismissed()
    }
}

extension SearchResultsViewController: SearchResultsDelegate {
    func clearSearch() {
        displaySearch.isSearching = false
        searchResults.clearSearch()
    }

    func performLocalSearch(searchTerm: String) {
        displaySearch.isSearching = true
        searchResults.searchLocally(term: searchTerm)
    }

    func performSearch(searchTerm: String, triggeredByTimer: Bool, completion: @escaping (() -> Void)) {
        displaySearch.isSearching = true
        if searchTerm.trim().isEmpty {
            completion()
        }

        if triggeredByTimer {
            searchResults.predictiveSearch(term: searchTerm)
        } else {
            searchResults.search(term: searchTerm)
        }

        if !triggeredByTimer, !searchTerm.trim().isEmpty {
            searchHistoryModel.add(searchTerm: searchTerm)
        }

        completion()
    }
}
