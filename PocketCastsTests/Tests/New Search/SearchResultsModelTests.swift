import Combine
import Foundation
import GRDB
import XCTest

@testable import PocketCastsDataModel
@testable import PocketCastsUtils
@testable import podcasts

/// Regression coverage for `SearchResultsModel`'s transcript-index path (P1-1):
/// `clearSearch()` resets `currentSearchTerm` to "" after the term was assigned,
/// so the async publish guard must not compare against that mutable string or
/// `transcriptHits` never publishes on the main search tab.
@MainActor
final class SearchResultsModelTests: XCTestCase {
    private let episodeUuid = "search-results-episode-uuid"
    private let podcastUuid = "search-results-podcast-uuid"

    private var dataManager: DataManager!
    private var dbPool: DatabasePool!
    private var workDirectory: URL!
    private var previousSharedManager: DataManager!
    private var cancellables = Set<AnyCancellable>()
    private let flagMock = FeatureFlagMock()

    override func setUp() async throws {
        try await super.setUp()

        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("search-results-model-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)

        // A private pool (rather than the shared manager's) so this suite can't
        // close the pool other suites hold on to.
        var configuration = Configuration()
        configuration.busyMode = .timeout(10)
        dbPool = try DatabasePool(path: workDirectory.appendingPathComponent("test.sqlite3").path, configuration: configuration)
        dataManager = try DataManager(dbQueue: GRDBQueue(dbPool: dbPool))

        // TranscriptSearchHitDisplay.displays(for:) resolves episode titles
        // through the shared manager, not the injected one.
        previousSharedManager = DataManager.sharedManager
        DataManager.sharedManager = dataManager

        flagMock.set(.transcriptSearch, value: true)

        var podcast = Podcast()
        podcast.uuid = podcastUuid
        podcast.addedDate = Date()
        _ = dataManager.save(podcast: podcast)
        var episode = Episode()
        episode.uuid = episodeUuid
        episode.podcastUuid = podcastUuid
        episode.title = "Indexed Episode"
        episode.addedDate = Date()
        dataManager.save(episode: episode)

        dataManager.transcriptSearch.replaceSegments(
            episodeUuid: episodeUuid,
            podcastUuid: podcastUuid,
            source: .provided,
            segments: [TranscriptSearchSegment(index: 0, text: "today we talk about spiral galaxies at length", startTime: 12)]
        )
    }

    override func tearDown() async throws {
        flagMock.reset()
        DataManager.sharedManager = previousSharedManager
        cancellables = []
        try? dbPool.close()
        try? FileManager.default.removeItem(at: workDirectory)
        try await super.tearDown()
    }

    private func makeModel() -> SearchResultsModel {
        SearchResultsModel(dataManager: dataManager)
    }

    func testTranscriptHitsPublishAfterSearch() async {
        let model = makeModel()
        XCTAssertTrue(dataManager.transcriptSearch.isAvailable, "FTS index unavailable; fixture setup failed")

        let published = expectation(description: "transcriptHits published a hit")
        model.$transcriptHits
            .filter { !$0.isEmpty }
            .first()
            .sink { _ in published.fulfill() }
            .store(in: &cancellables)

        model.search(term: "galaxies")

        await fulfillment(of: [published], timeout: 10)
        XCTAssertEqual(model.transcriptHits.map(\.episodeUuid), [episodeUuid])
    }

    func testSearchLeavesCurrentSearchTermSet() {
        let model = makeModel()

        model.search(term: "galaxies")

        XCTAssertEqual(model.currentSearchTerm, "galaxies",
                       "clearSearch() inside search(term:) must not wipe the just-assigned term")
    }

    func testClearSearchInvalidatesInFlightTranscriptQuery() async {
        let model = makeModel()

        let published = expectation(description: "transcriptHits published after clear")
        published.isInverted = true
        model.$transcriptHits
            .filter { !$0.isEmpty }
            .first()
            .sink { _ in published.fulfill() }
            .store(in: &cancellables)

        model.search(term: "galaxies")
        model.clearSearch()

        await fulfillment(of: [published], timeout: 2)
        XCTAssertTrue(model.transcriptHits.isEmpty, "A cleared search must not publish stale transcript hits")
    }
}
