import XCTest
import GRDB
@testable import PocketCastsDataModel
@testable import PocketCastsUtils

/// End-to-end coverage of the custom-playlist branch in the typed query builders:
/// all four `SelectClause` shapes execute against a seeded database, including the
/// `episodeUuidToAdd` OR-arm, search terms and sort types; unreadable envelopes and
/// the disabled feature flag render empty; and the legacy string builder's
/// intentional always-empty divergence is pinned.
final class PlaylistQueryBuilderCustomTests: DataManagerTestCase {

    private var dataManager: DataManager!
    private var originalSharedManager: DataManager!
    private let featureFlagMock = FeatureFlagMock()

    override func setUpWithError() throws {
        try super.setUpWithError()
        dataManager = DataManager.newTestDataManager()
        // The smart-rule fallback path reads unsubscribed uuids from the shared
        // manager at build time; point it at the fixture database (established
        // pattern, see PlaylistQueryBuilderParityTests).
        originalSharedManager = DataManager.sharedManager
        DataManager.sharedManager = dataManager
        featureFlagMock.set(.customPlaylists, value: true)

        try seedFixtures()
    }

    override func tearDownWithError() throws {
        DataManager.sharedManager = originalSharedManager
        featureFlagMock.reset()
        dataManager = nil
        try super.tearDownWithError()
    }

    /// Podcast A subscribed, podcast B unsubscribed (custom playlists must NOT
    /// force-exclude unsubscribed podcasts, unlike smart playlists). Durations and
    /// titles cover the search/sort/rule boundaries; one archived row pins the
    /// shared `archived = 0` handling.
    private func seedFixtures() throws {
        let podcastA = createTestPodcast(uuid: "podcast-a", title: "Alpha Show", subscribed: 1, dataManager: dataManager)
        let podcastB = createTestPodcast(uuid: "podcast-b", title: "Beta Show", subscribed: 0, dataManager: dataManager)

        seed(uuid: "ep-a1", podcast: podcastA, title: "Deep Interview", duration: 3600, addedOffset: -1)
        seed(uuid: "ep-a2", podcast: podcastA, title: "Quick News", duration: 300, addedOffset: -2)
        seed(uuid: "ep-b1", podcast: podcastB, title: "Beta Interview Special", duration: 5400, addedOffset: -3)
        seed(uuid: "ep-b2", podcast: podcastB, title: "Beta Shorts", duration: 120, addedOffset: -4)
        seed(uuid: "ep-arch", podcast: podcastA, title: "Archived Interview", duration: 4000, addedOffset: -5, archived: true)
    }

    private func seed(uuid: String, podcast: Podcast, title: String, duration: Double, addedOffset: TimeInterval, archived: Bool = false) {
        var episode = Episode()
        episode.uuid = uuid
        episode.podcastUuid = podcast.uuid
        episode.podcast_id = podcast.id
        episode.title = title
        episode.duration = duration
        episode.archived = archived
        episode.publishedDate = Date(timeIntervalSince1970: 1_700_000_000 + addedOffset)
        episode.addedDate = Date(timeIntervalSince1970: 1_700_000_000 + addedOffset)
        _ = dataManager.save(episode: episode)
    }

    private func makeCustomPlaylist(envelopeJSON: String?, sortType: PlaylistSort = .newestToOldest) -> EpisodeFilter {
        var playlist = EpisodeFilter()
        playlist.uuid = UUID().uuidString.lowercased()
        playlist.playlistName = "Custom"
        playlist.manual = false
        playlist.sortType = sortType.rawValue
        playlist.customQuery = envelopeJSON
        return dataManager.save(playlist: playlist)
    }

    private func durationOver1800Playlist(sortType: PlaylistSort = .newestToOldest) throws -> EpisodeFilter {
        let root = CustomQueryNode.condition(CustomQueryCondition(field: .duration, op: .greaterThan, value: .number(1800)))
        return makeCustomPlaylist(envelopeJSON: try CustomPlaylistQuery(root: root).envelopeJSON(), sortType: sortType)
    }

    // MARK: - The four typed clauses

    func testEpisodesClauseMatchesBuilderEnvelopeAcrossSubscriptionStates() throws {
        let playlist = try durationOver1800Playlist()

        let episodes = dataManager.episodes(matching: PlaylistQueryBuilder.episodesRequest(for: playlist))

        // ep-b1 belongs to an unsubscribed podcast and must still match; the
        // archived long episode must not.
        XCTAssertEqual(Set(episodes.map(\.uuid)), ["ep-a1", "ep-b1"])
    }

    func testEpisodeCountClause() throws {
        let playlist = try durationOver1800Playlist()

        let count = dataManager.count(matching: PlaylistQueryBuilder.countRequest(.episodeCount, for: playlist))
        XCTAssertEqual(count, 2)
    }

    func testAllEpisodeCountClauseIncludesArchivedWhenAsked() throws {
        let playlist = try durationOver1800Playlist()

        let hidden = dataManager.count(matching: PlaylistQueryBuilder.countRequest(.allEpisodeCount, for: playlist, shouldShowArchived: false))
        XCTAssertEqual(hidden, 2)

        let shown = dataManager.count(matching: PlaylistQueryBuilder.countRequest(.allEpisodeCount, for: playlist, shouldShowArchived: true))
        XCTAssertEqual(shown, 3, "archived matches count once the archived toggle is on")
    }

    func testFirstDistinctEpisodesClauseReturnsOnePerPodcast() throws {
        let root = CustomQueryNode.condition(CustomQueryCondition(field: .duration, op: .greaterThan, value: .number(0)))
        let playlist = makeCustomPlaylist(envelopeJSON: try CustomPlaylistQuery(root: root).envelopeJSON(), sortType: .newestToOldest)

        let request = PlaylistQueryBuilder.episodesRequest(.firstDistinctEpisodes, for: playlist, limit: 10)
        let episodes = dataManager.episodes(matching: request)

        XCTAssertEqual(episodes.map(\.uuid), ["ep-a1", "ep-b1"], "newest unarchived episode per podcast")
    }

    // MARK: - Shared query features

    func testEpisodeUuidToAddKeepsNonMatchingEpisodeVisible() throws {
        let playlist = try durationOver1800Playlist()

        let request = PlaylistQueryBuilder.episodesRequest(for: playlist, episodeUuidToAdd: "ep-a2")
        let episodes = dataManager.episodes(matching: request)

        XCTAssertEqual(Set(episodes.map(\.uuid)), ["ep-a1", "ep-a2", "ep-b1"], "the pinned uuid joins the custom matches")
    }

    func testSearchTermFiltersCustomMatches() throws {
        let playlist = try durationOver1800Playlist()

        let request = PlaylistQueryBuilder.episodesRequest(for: playlist, searchTerm: "beta")
        let episodes = dataManager.episodes(matching: request)

        XCTAssertEqual(episodes.map(\.uuid), ["ep-b1"], "case-insensitive match on episode or podcast title")
    }

    func testSortTypeOrdersCustomMatches() throws {
        let playlist = try durationOver1800Playlist(sortType: .shortestToLongest)

        let episodes = dataManager.episodes(matching: PlaylistQueryBuilder.episodesRequest(for: playlist)) // ep-a1 3600s, ep-b1 5400s
        XCTAssertEqual(episodes.map(\.uuid), ["ep-a1", "ep-b1"])

        let request = PlaylistQueryBuilder.episodesRequest(for: playlist, sortType: .longestToShortest)
        XCTAssertEqual(dataManager.episodes(matching: request).map(\.uuid), ["ep-b1", "ep-a1"], "explicit sortType overrides the playlist's")
    }

    func testLimitApplies() throws {
        let playlist = try durationOver1800Playlist(sortType: .longestToShortest)

        let request = PlaylistQueryBuilder.episodesRequest(for: playlist, limit: 1)
        XCTAssertEqual(dataManager.episodes(matching: request).map(\.uuid), ["ep-b1"])
    }

    // MARK: - SQL mode

    func testSQLModeEnvelopeExecutes() throws {
        let envelope = try CustomPlaylistQuery(sql: "episode.duration > 1800 AND podcast.title LIKE '%Show%'").envelopeJSON()
        let playlist = makeCustomPlaylist(envelopeJSON: envelope)

        let episodes = dataManager.episodes(matching: PlaylistQueryBuilder.episodesRequest(for: playlist))
        XCTAssertEqual(Set(episodes.map(\.uuid)), ["ep-a1", "ep-b1"])
    }

    func testSQLModeWithSubqueryExecutes() throws {
        let envelope = try CustomPlaylistQuery(sql: "episode.uuid IN (SELECT uuid FROM SJEpisode WHERE duration > 5000)").envelopeJSON()
        let playlist = makeCustomPlaylist(envelopeJSON: envelope)

        let episodes = dataManager.episodes(matching: PlaylistQueryBuilder.episodesRequest(for: playlist))
        XCTAssertEqual(episodes.map(\.uuid), ["ep-b1"])
    }

    func testSQLModeStatementSeparatorRendersEmpty() throws {
        let envelope = try CustomPlaylistQuery(sql: "1=1; DROP TABLE SJEpisode").envelopeJSON()
        let playlist = makeCustomPlaylist(envelopeJSON: envelope)

        XCTAssertTrue(dataManager.episodes(matching: PlaylistQueryBuilder.episodesRequest(for: playlist)).isEmpty)
        XCTAssertEqual(dataManager.count(matching: PlaylistQueryBuilder.countRequest(.episodeCount, for: playlist)), 0)
    }

    // MARK: - Render-empty states

    func testFlagOffRendersEmptyAcrossAllClauses() throws {
        let playlist = try durationOver1800Playlist()
        featureFlagMock.set(.customPlaylists, value: false)

        XCTAssertTrue(dataManager.episodes(matching: PlaylistQueryBuilder.episodesRequest(for: playlist)).isEmpty)
        XCTAssertTrue(dataManager.episodes(matching: PlaylistQueryBuilder.episodesRequest(.firstDistinctEpisodes, for: playlist, limit: 10)).isEmpty)
        XCTAssertEqual(dataManager.count(matching: PlaylistQueryBuilder.countRequest(.episodeCount, for: playlist)), 0)
        XCTAssertEqual(dataManager.count(matching: PlaylistQueryBuilder.countRequest(.allEpisodeCount, for: playlist)), 0)
    }

    func testUndecodableEnvelopeRendersEmptyNotCrashing() {
        let playlist = makeCustomPlaylist(envelopeJSON: "{ definitely not an envelope")

        XCTAssertTrue(dataManager.episodes(matching: PlaylistQueryBuilder.episodesRequest(for: playlist)).isEmpty)
        XCTAssertEqual(dataManager.count(matching: PlaylistQueryBuilder.countRequest(.episodeCount, for: playlist)), 0)
    }

    func testFutureVersionEnvelopeRendersEmpty() {
        let playlist = makeCustomPlaylist(envelopeJSON: #"{"version":99,"mode":"sql","sql":"1 = 1"}"#)

        XCTAssertTrue(dataManager.episodes(matching: PlaylistQueryBuilder.episodesRequest(for: playlist)).isEmpty)
    }

    func testCompilerRejectedASTRendersEmpty() throws {
        // duration/contains is outside the field catalog: compiles to (0).
        let root = CustomQueryNode.condition(CustomQueryCondition(field: .duration, op: .contains, value: .string("x")))
        let playlist = makeCustomPlaylist(envelopeJSON: try CustomPlaylistQuery(root: root).envelopeJSON())

        XCTAssertTrue(dataManager.episodes(matching: PlaylistQueryBuilder.episodesRequest(for: playlist)).isEmpty)
    }

    // MARK: - Legacy routing

    func testFilterEpisodesRequestRoutesCustomPlaylistsToJoinedQuery() throws {
        // The single-table fragment API (widgets/intents/autoplay) must serve custom
        // playlists through the joined shape, since fragments reference podcast.*.
        let envelope = try CustomPlaylistQuery(sql: "podcast.title LIKE '%Alpha%' AND episode.duration > 1800").envelopeJSON()
        let playlist = makeCustomPlaylist(envelopeJSON: envelope)

        let request = PlaylistQueryBuilder.filterEpisodesRequest(for: playlist, episodeUuidToAdd: nil, limit: 10)
        XCTAssertEqual(dataManager.episodes(matching: request).map(\.uuid), ["ep-a1"])
    }

    // MARK: - Seeding helper

    func testSmartRulesFragmentInlinesValuesAndStripsUnsubscribedExclusion() {
        var smart = EpisodeFilter()
        smart.uuid = UUID().uuidString.lowercased()
        smart.manual = false
        smart.filterUnplayed = true
        smart.filterDownloaded = true
        smart.filterNotDownloaded = true // all download statuses selected -> rule skipped
        smart.filterAllPodcasts = false
        smart.podcastUuids = "podcast-a,it's-quoted"
        smart.filterStarred = true

        let fragment = PlaylistQueryBuilder.smartRulesFragment(for: smart)

        XCTAssertEqual(
            fragment,
            "(episode.playingStatus = 1) AND episode.keepEpisode = 1 AND episode.podcastUuid IN ('podcast-a', 'it''s-quoted')"
        )
        XCTAssertFalse(fragment.contains("NOT IN"), "the unsubscribed exclusion must not be seeded")
    }

    func testSeededFragmentPassesTheValidator() throws {
        var smart = EpisodeFilter()
        smart.uuid = UUID().uuidString.lowercased()
        smart.manual = false
        smart.filterUnplayed = true
        smart.filterDuration = true
        smart.longerThan = 10
        smart.shorterThan = 60
        smart.filterHours = 24
        smart.filterAllPodcasts = false
        smart.podcastUuids = "podcast-a,podcast-b"

        let fragment = PlaylistQueryBuilder.smartRulesFragment(for: smart)
        XCTAssertFalse(fragment.isEmpty)

        // "Start from current rules" seeds directly into the SQL editor, so the
        // seeded text must always clear the save-time validation pipeline.
        let result = dataManager.validateCustomQueryFragment(fragment)
        XCTAssertNoThrow(try result.get())
    }

    func testSmartRulesFragmentIsEmptyWithNoActiveRules() {
        var smart = EpisodeFilter()
        smart.uuid = UUID().uuidString.lowercased()
        smart.manual = false
        smart.filterDownloaded = true
        smart.filterNotDownloaded = true

        XCTAssertEqual(PlaylistQueryBuilder.smartRulesFragment(for: smart), "")
    }

    func testLegacyStringBuilderRendersCustomPlaylistsEmptyByDesign() throws {
        // Pinned intentional divergence: the legacy golden reference renders custom
        // playlists as an always-empty rule group (custom is typed-first; do not add
        // custom fixtures to PlaylistQueryBuilderParityTests).
        let playlist = try durationOver1800Playlist()

        let query = PlaylistQueryBuilder.query(clause: .episode, for: playlist)
        XCTAssertTrue(dataManager.findPlaylistEpisodesWhere(query: query.sql, arguments: query.arguments).isEmpty)

        let fragment = PlaylistQueryBuilder.queryFor(filter: playlist, episodeUuidToAdd: nil, limit: 0)
        XCTAssertTrue(dataManager.findEpisodesWhere(customWhere: fragment.sql, arguments: fragment.arguments).isEmpty)
    }
}
