import SnapshotTesting
import XCTest

import PocketCastsDataModel
import PocketCastsUtils

final class PlaylistQueryBuilderSnapshotTests: XCTestCase {
    private let featureFlagStore = FeatureFlagOverrideStore()

    override func setUpWithError() throws {
        try super.setUpWithError()

        featureFlagStore.resetOverrides()
        try featureFlagStore.override(FeatureFlag.optimizeManualPlaylistQueries, withValue: true)
    }

    override func tearDown() {
        featureFlagStore.resetOverrides()

        super.tearDown()
    }

    func testOptimizedManualPlaylistEpisodeQuery() {
        var playlist = EpisodeFilter()
        playlist.manual = true
        playlist.uuid = "manual-playlist"
        playlist.sortType = PlaylistSort.dragAndDrop.rawValue

        let query = PlaylistQueryBuilder.query(
            clause: .episode,
            for: playlist,
            searchTerm: "chapter_50%\\bonus",
            limit: 25,
            shouldShowArchived: false
        )

        assertSnapshot(of: Self.describe(query), as: .lines)
    }

    func testSmartPlaylistFirstDistinctEpisodesQuery() {
        var playlist = EpisodeFilter()
        playlist.uuid = "smart-playlist"
        playlist.filterAudioVideoType = AudioVideoFilter.audioOnly.rawValue
        playlist.filterDownloaded = true
        playlist.filterDuration = true
        playlist.filterStarred = true
        playlist.filterUnplayed = true
        playlist.longerThan = 10
        playlist.shorterThan = 45
        playlist.podcastUuids = "podcast-a,podcast-b"
        playlist.sortType = PlaylistSort.longestToShortest.rawValue

        let query = PlaylistQueryBuilder.query(
            clause: .firstDistinctEpisodes,
            for: playlist,
            episodeUuidToAdd: "now-playing",
            searchTerm: "science_fiction%mix",
            limit: 50
        )

        assertSnapshot(of: Self.describe(query), as: .lines)
    }

    func testPodcastExistsQueries() {
        let queries = """
        excluding deleted:
        \(PlaylistQueryBuilder.podcastExistsInPlaylistEpisodesQuery())

        including deleted:
        \(PlaylistQueryBuilder.podcastExistsInPlaylistEpisodesQuery(includeDeleted: true))
        """

        assertSnapshot(of: queries, as: .lines)
    }

    func testManualPlaylistCountQueryVariants() throws {
        var playlist = EpisodeFilter()
        playlist.manual = true
        playlist.uuid = "manual-counts"

        let snapshot = try [
            describeManualQuery(
                named: "optimized episode count hidden",
                playlist: playlist,
                options: ManualQueryOptions(
                    clause: .episodeCount,
                    optimized: true,
                    shouldShowArchived: false
                )
            ),
            describeManualQuery(
                named: "optimized episode count shown",
                playlist: playlist,
                options: ManualQueryOptions(
                    clause: .episodeCount,
                    optimized: true,
                    shouldShowArchived: true
                )
            ),
            describeManualQuery(
                named: "optimized all episode count hidden",
                playlist: playlist,
                options: ManualQueryOptions(
                    clause: .allEpisodeCount,
                    optimized: true,
                    shouldShowArchived: false
                )
            ),
            describeManualQuery(
                named: "optimized all episode count shown",
                playlist: playlist,
                options: ManualQueryOptions(
                    clause: .allEpisodeCount,
                    optimized: true,
                    shouldShowArchived: true
                )
            ),
            describeManualQuery(
                named: "legacy episode count hidden",
                playlist: playlist,
                options: ManualQueryOptions(
                    clause: .episodeCount,
                    optimized: false,
                    shouldShowArchived: false
                )
            ),
            describeManualQuery(
                named: "legacy all episode count shown",
                playlist: playlist,
                options: ManualQueryOptions(
                    clause: .allEpisodeCount,
                    optimized: false,
                    shouldShowArchived: true
                )
            ),
        ].joined(separator: "\n\n---\n\n")

        assertSnapshot(of: snapshot, as: .lines)
    }

    func testManualPlaylistFirstDistinctQueryVariants() throws {
        var playlist = EpisodeFilter()
        playlist.manual = true
        playlist.uuid = "manual-first-distinct"

        let snapshot = try [
            describeManualQuery(
                named: "optimized custom order hidden with search",
                playlist: playlist,
                options: ManualQueryOptions(
                    clause: .firstDistinctEpisodes,
                    optimized: true,
                    searchTerm: "daily_mix",
                    limit: 15,
                    shouldShowArchived: false,
                    sortType: .dragAndDrop
                )
            ),
            describeManualQuery(
                named: "optimized newest shown with search",
                playlist: playlist,
                options: ManualQueryOptions(
                    clause: .firstDistinctEpisodes,
                    optimized: true,
                    searchTerm: "daily_mix",
                    limit: 15,
                    shouldShowArchived: true,
                    sortType: .newestToOldest
                )
            ),
            describeManualQuery(
                named: "legacy custom order hidden with search",
                playlist: playlist,
                options: ManualQueryOptions(
                    clause: .firstDistinctEpisodes,
                    optimized: false,
                    searchTerm: "daily_mix",
                    limit: 15,
                    shouldShowArchived: false,
                    sortType: .dragAndDrop
                )
            ),
            describeManualQuery(
                named: "legacy shortest shown",
                playlist: playlist,
                options: ManualQueryOptions(
                    clause: .firstDistinctEpisodes,
                    optimized: false,
                    limit: 15,
                    shouldShowArchived: true,
                    sortType: .shortestToLongest
                )
            ),
        ].joined(separator: "\n\n---\n\n")

        assertSnapshot(of: snapshot, as: .lines)
    }

    func testSmartPlaylistQueryVariants() {
        var filteredPlaylist = EpisodeFilter()
        filteredPlaylist.uuid = "smart-filtered"
        filteredPlaylist.filterAudioVideoType = AudioVideoFilter.videoOnly.rawValue
        filteredPlaylist.filterDuration = true
        filteredPlaylist.filterFinished = true
        filteredPlaylist.filterNotDownloaded = true
        filteredPlaylist.filterHours = 72
        filteredPlaylist.filterPartiallyPlayed = true
        filteredPlaylist.filterStarred = true
        filteredPlaylist.longerThan = 5
        filteredPlaylist.shorterThan = 90
        filteredPlaylist.podcastUuids = "podcast-red,podcast-blue"
        filteredPlaylist.sortType = PlaylistSort.oldestToNewest.rawValue

        var emptyPlaylist = EpisodeFilter()
        emptyPlaylist.uuid = "smart-empty"

        let snapshot = [
            Self.describe(
                named: "filtered episode query",
                PlaylistQueryBuilder.query(
                    clause: .episode,
                    for: filteredPlaylist,
                    episodeUuidToAdd: "pinned-episode",
                    searchTerm: "news\\nightly",
                    limit: 20
                )
            ),
            Self.describe(
                named: "filtered episode count hidden",
                PlaylistQueryBuilder.query(
                    clause: .episodeCount,
                    for: filteredPlaylist,
                    shouldShowArchived: false
                )
            ),
            Self.describe(
                named: "filtered all episode count shown",
                PlaylistQueryBuilder.query(
                    clause: .allEpisodeCount,
                    for: filteredPlaylist,
                    shouldShowArchived: true
                )
            ),
            Self.describe(
                named: "empty episode count",
                PlaylistQueryBuilder.query(
                    clause: .episodeCount,
                    for: emptyPlaylist
                )
            ),
        ].joined(separator: "\n\n---\n\n")

        assertSnapshot(of: snapshot, as: .lines)
    }

    func testLegacySmartPlaylistQueryForVariants() {
        var filteredPlaylist = EpisodeFilter()
        filteredPlaylist.filterAudioVideoType = AudioVideoFilter.audioOnly.rawValue
        filteredPlaylist.filterDownloaded = true
        filteredPlaylist.filterDuration = true
        filteredPlaylist.filterHours = 48
        filteredPlaylist.filterPartiallyPlayed = true
        filteredPlaylist.filterStarred = true
        filteredPlaylist.longerThan = 12
        filteredPlaylist.shorterThan = 40
        filteredPlaylist.podcastUuids = "podcast-alpha,podcast-beta"
        filteredPlaylist.sortType = PlaylistSort.shortestToLongest.rawValue

        var noFilterPlaylist = EpisodeFilter()
        noFilterPlaylist.sortType = PlaylistSort.longestToShortest.rawValue

        let snapshot = [
            Self.describe(
                named: "filtered legacy query with pinned episode",
                PlaylistQueryBuilder.queryFor(
                    filter: filteredPlaylist,
                    episodeUuidToAdd: "legacy-pinned",
                    limit: 30
                )
            ),
            Self.describe(
                named: "empty legacy query without pinned episode",
                PlaylistQueryBuilder.queryFor(
                    filter: noFilterPlaylist,
                    episodeUuidToAdd: nil,
                    limit: 0
                )
            ),
        ].joined(separator: "\n\n---\n\n")

        assertSnapshot(of: snapshot, as: .lines)
    }

    private static func describe(_ query: (sql: String, arguments: [Any])) -> String {
        """
        SQL:
        \(normalize(query.sql.trimmingCharacters(in: .whitespacesAndNewlines)))

        Arguments:
        \(describe(query.arguments))
        """
    }

    private static func describe(named name: String, _ query: (sql: String, arguments: [Any])) -> String {
        """
        \(name)

        \(describe(query))
        """
    }

    private struct ManualQueryOptions {
        let clause: PlaylistQueryBuilder.SelectClause
        let optimized: Bool
        var searchTerm: String? = nil
        var limit = 0
        let shouldShowArchived: Bool
        var sortType: PlaylistSort? = nil
    }

    private func describeManualQuery(
        named name: String,
        playlist: EpisodeFilter,
        options: ManualQueryOptions
    ) throws -> String {
        try featureFlagStore.override(FeatureFlag.optimizeManualPlaylistQueries, withValue: options.optimized)

        return Self.describe(
            named: name,
            PlaylistQueryBuilder.query(
                clause: options.clause,
                for: playlist,
                searchTerm: options.searchTerm,
                limit: options.limit,
                shouldShowArchived: options.shouldShowArchived,
                sortType: options.sortType
            )
        )
    }

    private static func describe(_ arguments: [Any]) -> String {
        guard !arguments.isEmpty else { return "[]" }

        return arguments.enumerated()
            .map { index, argument in "\(index + 1). \(String(describing: argument))" }
            .joined(separator: "\n")
    }

    private static func normalize(_ sql: String) -> String {
        trimTrailingWhitespace(
            sql.replacingOccurrences(
                of: #"publishedDate > -?\d+(?:\.\d+)?"#,
                with: "publishedDate > <relative-time>",
                options: .regularExpression
            )
        )
    }

    private static func trimTrailingWhitespace(_ value: String) -> String {
        value.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                var line = String(line)
                while line.last?.isWhitespace == true {
                    line.removeLast()
                }
                return line
            }
            .joined(separator: "\n")
    }
}
