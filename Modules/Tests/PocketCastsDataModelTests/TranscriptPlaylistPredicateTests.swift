import XCTest
import GRDB
@testable import PocketCastsDataModel
@testable import PocketCastsUtils

/// End-to-end coverage of the custom-playlist "transcript mentions" predicate
/// against a seeded database with a live FTS index: playlist membership and counts,
/// both corpus sources, ANY-group interplay, the flag-off render-empty contract,
/// prefix matching, and SQL-mode validation of a hand-written MATCH subquery.
final class TranscriptPlaylistPredicateTests: DataManagerTestCase {

    private var dataManager: DataManager!
    private var originalSharedManager: DataManager!
    private let featureFlagMock = FeatureFlagMock()

    override func setUpWithError() throws {
        try super.setUpWithError()
        dataManager = DataManager.newTestDataManager()
        // customRuleFragment resolves capabilities against the shared manager's
        // transcript index (established pattern, see PlaylistQueryBuilderCustomTests).
        originalSharedManager = DataManager.sharedManager
        DataManager.sharedManager = dataManager
        featureFlagMock.set(.customPlaylists, value: true)
        featureFlagMock.set(.transcriptSearch, value: true)
        featureFlagMock.set(.transcriptPlaylistPredicates, value: true)

        try XCTSkipUnless(dataManager.transcriptSearch.isAvailable, "requires an FTS5-capable SQLite build")
        try seedFixtures()
    }

    override func tearDownWithError() throws {
        DataManager.sharedManager = originalSharedManager
        featureFlagMock.reset()
        dataManager = nil
        try super.tearDownWithError()
    }

    /// Three episodes: one with a provided-source transcript mentioning climate,
    /// one with a generated-source transcript mentioning quantum, one with no
    /// indexed transcript at all (the partial-index case the predicate must
    /// silently not match).
    private func seedFixtures() throws {
        let podcast = createTestPodcast(uuid: "podcast-t", title: "Transcript Show", dataManager: dataManager)

        seed(uuid: "ep-climate", podcast: podcast, title: "Weather News Special")
        seed(uuid: "ep-quantum", podcast: podcast, title: "Physics Hour")
        seed(uuid: "ep-plain", podcast: podcast, title: "Plain News Episode")

        dataManager.transcriptSearch.replaceSegments(
            episodeUuid: "ep-climate",
            podcastUuid: podcast.uuid,
            source: .provided,
            segments: [
                TranscriptSearchSegment(index: 0, text: "Today we talk about climate change and interest rates.", startTime: 0),
                TranscriptSearchSegment(index: 1, text: "The climate debate continued after the break.", startTime: 42)
            ]
        )
        dataManager.transcriptSearch.replaceSegments(
            episodeUuid: "ep-quantum",
            podcastUuid: podcast.uuid,
            source: .generated,
            segments: [
                TranscriptSearchSegment(index: 0, text: "Quantum entanglement explained for beginners.", startTime: 10, speaker: "Speaker 1")
            ]
        )
    }

    private func seed(uuid: String, podcast: Podcast, title: String) {
        var episode = Episode()
        episode.uuid = uuid
        episode.podcastUuid = podcast.uuid
        episode.podcast_id = podcast.id
        episode.title = title
        episode.duration = 1800
        episode.publishedDate = Date(timeIntervalSince1970: 1_700_000_000)
        episode.addedDate = Date(timeIntervalSince1970: 1_700_000_000)
        _ = dataManager.save(episode: episode)
    }

    private func makePlaylist(root: CustomQueryNode) throws -> EpisodeFilter {
        var playlist = EpisodeFilter()
        playlist.uuid = UUID().uuidString.lowercased()
        playlist.playlistName = "Transcript Custom"
        playlist.manual = false
        playlist.sortType = PlaylistSort.newestToOldest.rawValue
        playlist.customQuery = try CustomPlaylistQuery(root: root).envelopeJSON()
        return dataManager.save(playlist: playlist)
    }

    private func mentions(_ term: String) -> CustomQueryNode {
        .condition(CustomQueryCondition(field: .transcriptMentions, op: .mentions, value: .string(term), secondValue: nil))
    }

    // MARK: - Membership

    func testPlaylistContainsOnlyIndexedEpisodesMentioningTerm() throws {
        let playlist = try makePlaylist(root: mentions("climate"))

        let episodes = dataManager.episodes(matching: PlaylistQueryBuilder.episodesRequest(for: playlist))

        // ep-plain has no indexed transcript: positive-only semantics mean it can
        // never match, and ep-quantum's transcript doesn't mention the term.
        XCTAssertEqual(episodes.map(\.uuid), ["ep-climate"])

        let count = dataManager.count(matching: PlaylistQueryBuilder.countRequest(.episodeCount, for: playlist))
        XCTAssertEqual(count, 1)
    }

    func testPredicateMatchesGeneratedSourceSegments() throws {
        let playlist = try makePlaylist(root: mentions("quantum entanglement"))

        let episodes = dataManager.episodes(matching: PlaylistQueryBuilder.episodesRequest(for: playlist))
        XCTAssertEqual(episodes.map(\.uuid), ["ep-quantum"], "the predicate is source-agnostic")
    }

    func testLastTokenMatchesByPrefix() throws {
        // sanitizeFTSQuery star-suffixes the last token: "clim" matches "climate".
        let playlist = try makePlaylist(root: mentions("clim"))

        let episodes = dataManager.episodes(matching: PlaylistQueryBuilder.episodesRequest(for: playlist))
        XCTAssertEqual(episodes.map(\.uuid), ["ep-climate"])
    }

    // MARK: - Group interplay

    func testAnyGroupTitleArmSurvivesTranscriptArmMiss() throws {
        let root = CustomQueryNode.group(CustomQueryGroup(op: .any, children: [
            mentions("xyzzy"),
            .condition(CustomQueryCondition(field: .episodeTitle, op: .contains, value: .string("News"), secondValue: nil))
        ]))
        let playlist = try makePlaylist(root: root)

        let episodes = dataManager.episodes(matching: PlaylistQueryBuilder.episodesRequest(for: playlist))
        XCTAssertEqual(Set(episodes.map(\.uuid)), ["ep-climate", "ep-plain"], "title matches survive a missing transcript arm")
    }

    func testAllGroupCombinesTranscriptAndMetadataArms() throws {
        let root = CustomQueryNode.group(CustomQueryGroup(op: .all, children: [
            mentions("climate"),
            .condition(CustomQueryCondition(field: .duration, op: .greaterThan, value: .number(600), secondValue: nil))
        ]))
        let playlist = try makePlaylist(root: root)

        let episodes = dataManager.episodes(matching: PlaylistQueryBuilder.episodesRequest(for: playlist))
        XCTAssertEqual(episodes.map(\.uuid), ["ep-climate"])
    }

    // MARK: - Capability gating

    func testFlagOffDarkensTheConditionNotThePlaylist() throws {
        featureFlagMock.set(.transcriptPlaylistPredicates, value: false)

        let solo = try makePlaylist(root: mentions("climate"))
        XCTAssertTrue(dataManager.episodes(matching: PlaylistQueryBuilder.episodesRequest(for: solo)).isEmpty,
                      "a lone transcript condition renders always-false")

        let anyGroup = try makePlaylist(root: .group(CustomQueryGroup(op: .any, children: [
            mentions("climate"),
            .condition(CustomQueryCondition(field: .episodeTitle, op: .contains, value: .string("Physics"), secondValue: nil))
        ])))
        let episodes = dataManager.episodes(matching: PlaylistQueryBuilder.episodesRequest(for: anyGroup))
        XCTAssertEqual(episodes.map(\.uuid), ["ep-quantum"], "other ANY arms keep working with the flag off")
    }

    // MARK: - SQL mode

    func testSQLModeMatchSubqueryPassesValidation() throws {
        let fragment = "episode.uuid IN (SELECT episodeUuid FROM TranscriptSegmentIndex WHERE TranscriptSegmentIndex MATCH '\"climate\"')"
        let result = dataManager.validateCustomQueryFragment(fragment)
        XCTAssertEqual(try result.get(), 1, "a MATCH subquery is read-only and trial-executes against the seeded index")
    }
}
