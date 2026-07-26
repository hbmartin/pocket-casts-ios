import PocketCastsDataModel
import Testing
import UIKit

@testable import podcasts

@MainActor
@Suite("Diffable refresh regressions")
struct DiffableRefreshRegressionTests {
    private struct SelectionModel: Equatable {
        let id: String
        let revision: Int
    }

    @Test("A superseded refresh cannot mutate the current UI state")
    func refreshGateRejectsSupersededAndInvalidatedGenerations() {
        var gate = LatestRefreshGate()

        let first = gate.begin()
        let second = gate.begin()

        #expect(!gate.isCurrent(first))
        #expect(gate.isCurrent(second))

        gate.invalidate()

        #expect(!gate.isCurrent(second))
    }

    @Test("Selections retain current models and discard removed identifiers")
    func selectedValueModelsAreRefreshed() {
        let selected = [
            SelectionModel(id: "retained", revision: 1),
            SelectionModel(id: "removed", revision: 1),
        ]
        let current = [
            "retained": SelectionModel(id: "retained", revision: 2),
            "inserted": SelectionModel(id: "inserted", revision: 1),
        ]

        let refreshed = DiffableHelpers.refreshedSelection(selected, id: \.id, modelsByID: current)

        #expect(refreshed == [SelectionModel(id: "retained", revision: 2)])
    }

    @Test("Snapshot completion runs after the table data source installs the snapshot", arguments: [false, true])
    func snapshotCompletionRunsAfterApply(animated: Bool) async {
        let tableView = UITableView()
        let dataSource = UITableViewDiffableDataSource<String, String>(tableView: tableView) { _, _, _ in
            UITableViewCell()
        }
        let snapshot = DiffableHelpers.snapshot(sections: [(section: "section", items: ["episode"])])

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DiffableHelpers.apply(
                snapshot,
                to: dataSource,
                animatingDifferences: animated,
                context: "DiffableRefreshRegressionTests"
            ) {
                #expect(dataSource.snapshot().itemIdentifiers == ["episode"])
                continuation.resume()
            }
        }
    }

    @Test("Downloaded episode fingerprints include visible date and episode metadata")
    func downloadedEpisodeFingerprintIncludesVisibleMetadata() {
        var episode = Episode()
        episode.uuid = "episode"
        let original = ListEpisode(episode: episode, tintColor: .systemBlue).renderFingerprint

        var datedEpisode = episode
        datedEpisode.publishedDate = Date(timeIntervalSince1970: 1)
        #expect(ListEpisode(episode: datedEpisode, tintColor: .systemBlue).renderFingerprint != original)

        var numberedEpisode = episode
        numberedEpisode.episodeNumber = 12
        numberedEpisode.seasonNumber = 3
        #expect(ListEpisode(episode: numberedEpisode, tintColor: .systemBlue).renderFingerprint != original)

        episode.episodeType = "bonus"
        #expect(ListEpisode(episode: episode, tintColor: .systemBlue).renderFingerprint != original)
    }

    @Test("Uploaded episode fingerprints include bookmark and visible metadata changes")
    func uploadedEpisodeFingerprintIncludesBookmarksAndMetadata() {
        var episode = UserEpisode()
        episode.uuid = "upload"
        let original = episode.renderFingerprint(hasBookmarks: false)

        #expect(episode.renderFingerprint(hasBookmarks: true) != original)

        var datedEpisode = episode
        datedEpisode.publishedDate = Date(timeIntervalSince1970: 1)
        #expect(datedEpisode.renderFingerprint(hasBookmarks: false) != original)

        episode.fileType = "audio/mp4"
        #expect(episode.renderFingerprint(hasBookmarks: false) != original)
    }

    @Test("Folder podcast fingerprints include author and paid state")
    func podcastFingerprintIncludesVisibleMetadata() {
        var podcast = Podcast()
        podcast.uuid = "podcast"
        let original = podcast.renderFingerprint

        var authoredPodcast = podcast
        authoredPodcast.author = "Updated author"
        #expect(authoredPodcast.renderFingerprint != original)

        podcast.isPaid = true
        #expect(podcast.renderFingerprint != original)
    }
}
