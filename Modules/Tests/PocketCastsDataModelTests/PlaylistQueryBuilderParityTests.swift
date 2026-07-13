import XCTest
import GRDB
@testable import PocketCastsDataModel
@testable import PocketCastsUtils

/// Row-set parity between the legacy string-assembled playlist queries
/// (`PlaylistQueryBuilder.query`/`queryFor`/`podcastExistsInPlaylistEpisodesQuery`,
/// executed through the raw-SQL `findPlaylistEpisodesWhere`/`findEpisodesWhere`/
/// `count(query:values:)` paths) and the typed `SQLRequest` implementations
/// (`episodesRequest`/`countRequest`/`filterEpisodesRequest`/
/// `podcastExistsInPlaylistEpisodesRequest`, executed through
/// `episodes(matching:)`/`count(matching:)`/`exists(matching:)`).
///
/// The legacy builder is the frozen golden reference; parity is asserted on the
/// fetched rows (ordered episode ids and uuids, count values), never on SQL text.
/// Legacy quirks are pinned, not fixed: both sides must agree even where the
/// legacy SQL errors at runtime and yields nothing (e.g. smart playlists sorted
/// by drag-and-drop). Sanity assertions guard the known-nonempty configurations
/// so parity can't pass vacuously on two empty results.
final class PlaylistQueryBuilderParityTests: DataManagerTestCase {

    private var dataManager: DataManager!
    private var originalSharedManager: DataManager!
    private let featureFlagMock = FeatureFlagMock()

    // Fixture handles
    private var manualPlaylist: EpisodeFilter!
    private var podcastA: Podcast!
    private var podcastB: Podcast!
    private var podcastC: Podcast!

    /// Uuid of an episode excluded by several smart rules (playingStatus = completed),
    /// used to exercise the `episodeUuidToAdd` OR-arm.
    private let pinnedEpisodeUuid = "ep-a5"

    override func setUpWithError() throws {
        try super.setUpWithError()

        dataManager = DataManager.newTestDataManager()
        // Both the legacy and typed smart-rule builders read unsubscribed podcast
        // uuids from the shared manager at query-build time, so point it at the
        // fixture database (established pattern, see SyncTaskPlaylistOrderingTests).
        originalSharedManager = DataManager.sharedManager
        DataManager.sharedManager = dataManager

        try seedFixtures()
    }

    override func tearDownWithError() throws {
        DataManager.sharedManager = originalSharedManager
        featureFlagMock.reset()
        dataManager = nil
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    /// Podcasts: A and B subscribed, C unsubscribed (exercises the NOT IN rule that
    /// both builders read from the shared manager).
    ///
    /// Episodes cover every smart-rule predicate boundary: all three playing
    /// statuses; all six download statuses; audio/video/nil file types; duration
    /// exactly at both window boundaries (600 = 10m lower bound, 659 = 10m59s upper
    /// bound); starred; archived; published dates inside and outside a 24h window;
    /// titles with LIKE-hostile characters (quote, %, _). One uuid ("ep-dup") has
    /// two episode rows with different archived/download states so the manual
    /// dedupe window's CASE ordering differs between the two feature-flag shapes.
    /// addedDate is unique per row so every ORDER BY is a total order.
    private func seedFixtures() throws {
        let now = Date()

        podcastA = createTestPodcast(uuid: "podcast-a", title: "Alpha Show", subscribed: 1, dataManager: dataManager)
        podcastB = createTestPodcast(uuid: "podcast-b", title: "Beta Show", subscribed: 1, dataManager: dataManager)
        podcastC = createTestPodcast(uuid: "podcast-c", title: "Gamma Show", subscribed: 0, dataManager: dataManager)

        var added = 0
        func nextAddedDate() -> Date {
            added += 1
            return now.addingTimeInterval(TimeInterval(-added))
        }

        let a1 = seedEpisode(uuid: "ep-a1", podcast: podcastA, title: "Morning Run Episode",
                             playingStatus: .notPlayed, episodeStatus: .notDownloaded, fileType: "audio/mp3",
                             duration: 300, starred: false, archived: false,
                             publishedDate: now.addingTimeInterval(-1800), addedDate: nextAddedDate())
        let a2 = seedEpisode(uuid: "ep-a2", podcast: podcastA, title: "Deep Dive Video",
                             playingStatus: .inProgress, episodeStatus: .downloaded, fileType: "video/mp4",
                             duration: 1800, starred: true, archived: false,
                             publishedDate: now.addingTimeInterval(-259200), addedDate: nextAddedDate())
        let a3 = seedEpisode(uuid: "ep-a3", podcast: podcastA, title: "Archived Classic Episode",
                             playingStatus: .completed, episodeStatus: .downloadFailed, fileType: "audio/mp3",
                             duration: 659, starred: false, archived: true,
                             publishedDate: now.addingTimeInterval(-259200 - 60), addedDate: nextAddedDate())
        let a4 = seedEpisode(uuid: "ep-a4", podcast: podcastA, title: "Boundary Episode",
                             playingStatus: .notPlayed, episodeStatus: .queued, fileType: nil,
                             duration: 600, starred: false, archived: false,
                             publishedDate: now.addingTimeInterval(-7200), addedDate: nextAddedDate())
        let a5 = seedEpisode(uuid: pinnedEpisodeUuid, podcast: podcastA, title: "Completed Special",
                             playingStatus: .completed, episodeStatus: .waitingForWifi, fileType: "audio/mp3",
                             duration: 660, starred: true, archived: false,
                             publishedDate: now.addingTimeInterval(-172800), addedDate: nextAddedDate())
        let b1 = seedEpisode(uuid: "ep-b1", podcast: podcastB, title: "O'Brien 100% Special_Edition",
                             playingStatus: .notPlayed, episodeStatus: .downloading, fileType: "audio/mp3",
                             duration: 3600, starred: false, archived: false,
                             publishedDate: now.addingTimeInterval(-864000), addedDate: nextAddedDate())
        let b2 = seedEpisode(uuid: "ep-b2", podcast: podcastB, title: "Episode Two B",
                             playingStatus: .inProgress, episodeStatus: .notDownloaded, fileType: "video/mp4",
                             duration: 120, starred: false, archived: false,
                             publishedDate: now.addingTimeInterval(-3600), addedDate: nextAddedDate())
        // Duplicate uuid pair: same episode uuid, different podcast rows, different
        // archived/download states.
        let dupA = seedEpisode(uuid: "ep-dup", podcast: podcastA, title: "Duplicate Alpha Episode",
                               playingStatus: .notPlayed, episodeStatus: .notDownloaded, fileType: "audio/mp3",
                               duration: 900, starred: false, archived: false,
                               publishedDate: now.addingTimeInterval(-5000), addedDate: nextAddedDate())
        _ = seedEpisode(uuid: "ep-dup", podcast: podcastB, title: "Duplicate Beta Episode",
                        playingStatus: .notPlayed, episodeStatus: .downloaded, fileType: "audio/mp3",
                        duration: 900, starred: false, archived: true,
                        publishedDate: now.addingTimeInterval(-5000), addedDate: nextAddedDate())
        let c1 = seedEpisode(uuid: "ep-c1", podcast: podcastC, title: "Unsubscribed Episode",
                             playingStatus: .notPlayed, episodeStatus: .notDownloaded, fileType: "audio/mp3",
                             duration: 600, starred: false, archived: false,
                             publishedDate: now.addingTimeInterval(-3600), addedDate: nextAddedDate())

        manualPlaylist = createTestPlaylist(uuid: "manual-playlist", name: "Manual", manual: true, dataManager: dataManager)

        // A ghost row (playlist entry without a matching episode row) must simply
        // drop out of every query.
        var ghost = Episode()
        ghost.uuid = "ghost-episode"
        ghost.podcastUuid = "podcast-ghost"

        XCTAssertTrue(dataManager.add(episodes: [a1, a2, a3, a4, a5, b1, b2, dupA, c1, ghost], to: manualPlaylist))
    }

    @discardableResult
    private func seedEpisode(
        uuid: String,
        podcast: Podcast,
        title: String,
        playingStatus: PlayingStatus,
        episodeStatus: DownloadStatus,
        fileType: String?,
        duration: Double,
        starred: Bool,
        archived: Bool,
        publishedDate: Date,
        addedDate: Date
    ) -> Episode {
        var episode = Episode()
        episode.uuid = uuid
        episode.podcastUuid = podcast.uuid
        episode.podcast_id = podcast.id
        episode.title = title
        episode.playingStatus = playingStatus.rawValue
        episode.episodeStatus = episodeStatus.rawValue
        episode.fileType = fileType
        episode.duration = duration
        episode.keepEpisode = starred
        episode.archived = archived
        episode.publishedDate = publishedDate
        episode.addedDate = addedDate
        return dataManager.save(episode: episode)
    }

    /// Smart-playlist fixtures, one per rule plus edge combinations.
    ///
    /// `EpisodeFilter.filterDownloading` is a `let` constant that is always true, so
    /// a bare filter carries an implicit queued/downloading rule. Like the filters
    /// the app creates, the baseline here selects all download statuses (rule
    /// skipped); the download fixtures override that, and `downloadingImplicit`
    /// covers the bare-object shape.
    private func smartFixtures() -> [(name: String, filter: EpisodeFilter)] {
        func filter(_ name: String, _ configure: (inout EpisodeFilter) -> Void) -> (String, EpisodeFilter) {
            var playlist = EpisodeFilter()
            playlist.manual = false
            playlist.uuid = "smart-\(name)"
            playlist.filterDownloaded = true
            playlist.filterNotDownloaded = true
            configure(&playlist)
            return (name, playlist)
        }

        return [
            filter("unsubscribedRuleOnly") { _ in },
            filter("unplayedOnly") { $0.filterUnplayed = true },
            filter("partialAndFinished") { $0.filterPartiallyPlayed = true; $0.filterFinished = true },
            filter("allPlayingStatuses") { $0.filterUnplayed = true; $0.filterPartiallyPlayed = true; $0.filterFinished = true },
            filter("downloadedOnly") { $0.filterDownloaded = true; $0.filterNotDownloaded = false },
            filter("downloadingImplicit") { $0.filterDownloaded = false; $0.filterNotDownloaded = false },
            filter("notDownloadedOnly") { $0.filterDownloaded = false; $0.filterNotDownloaded = true },
            filter("audioOnly") { $0.filterAudioVideoType = AudioVideoFilter.audioOnly.rawValue },
            filter("videoOnly") { $0.filterAudioVideoType = AudioVideoFilter.videoOnly.rawValue },
            filter("durationWindow") {
                $0.filterDuration = true
                $0.longerThan = 10
                $0.shorterThan = 10
                $0.sortType = PlaylistSort.shortestToLongest.rawValue
            },
            filter("starredOnly") { $0.filterStarred = true },
            filter("specificPodcasts") {
                $0.filterAllPodcasts = false
                $0.podcastUuids = "podcast-a,podcast-b"
                $0.sortType = PlaylistSort.oldestToNewest.rawValue
            },
            filter("recentHours") { $0.filterHours = 24 },
            filter("combined") {
                $0.filterUnplayed = true
                $0.filterDownloaded = false
                $0.filterAudioVideoType = AudioVideoFilter.audioOnly.rawValue
                $0.filterDuration = true
                $0.longerThan = 0
                $0.shorterThan = 10
                $0.filterHours = 24
            }
        ]
    }

    // MARK: - Comparison helpers

    private func legacyEpisodes(
        clause: PlaylistQueryBuilder.SelectClause,
        playlist: EpisodeFilter,
        episodeUuidToAdd: String?,
        searchTerm: String?,
        limit: Int,
        shouldShowArchived: Bool,
        sortType: PlaylistSort?
    ) -> [Episode] {
        let query = PlaylistQueryBuilder.query(
            clause: clause,
            for: playlist,
            episodeUuidToAdd: episodeUuidToAdd,
            searchTerm: searchTerm,
            limit: limit,
            shouldShowArchived: shouldShowArchived,
            sortType: sortType
        )
        return dataManager.findPlaylistEpisodesWhere(query: query.sql, arguments: query.arguments)
    }

    private func typedEpisodes(
        selection: PlaylistQueryBuilder.EpisodeSelection,
        playlist: EpisodeFilter,
        episodeUuidToAdd: String?,
        searchTerm: String?,
        limit: Int,
        shouldShowArchived: Bool,
        sortType: PlaylistSort?
    ) -> [Episode] {
        let request = PlaylistQueryBuilder.episodesRequest(
            selection,
            for: playlist,
            episodeUuidToAdd: episodeUuidToAdd,
            searchTerm: searchTerm,
            limit: limit,
            shouldShowArchived: shouldShowArchived,
            sortType: sortType
        )
        return dataManager.episodes(matching: request)
    }

    /// Asserts ordered row parity for one configuration of the episode-returning clauses.
    /// Returns the legacy rows so callers can add non-vacuousness assertions.
    @discardableResult
    private func assertEpisodeParity(
        clause: PlaylistQueryBuilder.SelectClause,
        selection: PlaylistQueryBuilder.EpisodeSelection,
        playlist: EpisodeFilter,
        episodeUuidToAdd: String?,
        searchTerm: String?,
        limit: Int,
        shouldShowArchived: Bool,
        sortType: PlaylistSort?,
        _ config: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [Episode] {
        let legacy = legacyEpisodes(clause: clause, playlist: playlist, episodeUuidToAdd: episodeUuidToAdd, searchTerm: searchTerm, limit: limit, shouldShowArchived: shouldShowArchived, sortType: sortType)
        let typed = typedEpisodes(selection: selection, playlist: playlist, episodeUuidToAdd: episodeUuidToAdd, searchTerm: searchTerm, limit: limit, shouldShowArchived: shouldShowArchived, sortType: sortType)

        XCTAssertEqual(legacy.map(\.id), typed.map(\.id), "Episode id order mismatch: \(config)", file: file, line: line)
        XCTAssertEqual(legacy.map(\.uuid), typed.map(\.uuid), "Episode uuid order mismatch: \(config)", file: file, line: line)
        return legacy
    }

    /// Asserts count parity for one configuration of the count clauses.
    /// Returns the legacy count so callers can add non-vacuousness assertions.
    @discardableResult
    private func assertCountParity(
        clause: PlaylistQueryBuilder.SelectClause,
        selection: PlaylistQueryBuilder.CountSelection,
        playlist: EpisodeFilter,
        episodeUuidToAdd: String?,
        searchTerm: String?,
        shouldShowArchived: Bool,
        _ config: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Int {
        let query = PlaylistQueryBuilder.query(
            clause: clause,
            for: playlist,
            episodeUuidToAdd: episodeUuidToAdd,
            searchTerm: searchTerm,
            shouldShowArchived: shouldShowArchived
        )
        let legacy = dataManager.count(query: query.sql, values: query.arguments)

        let request = PlaylistQueryBuilder.countRequest(
            selection,
            for: playlist,
            episodeUuidToAdd: episodeUuidToAdd,
            searchTerm: searchTerm,
            shouldShowArchived: shouldShowArchived
        )
        let typed = dataManager.count(matching: request)

        XCTAssertEqual(legacy, typed, "Count mismatch: \(config)", file: file, line: line)
        return legacy
    }

    // MARK: - Manual playlists

    func testManualEpisodeAndFirstDistinctParityMatrix() {
        let sorts: [PlaylistSort] = [.newestToOldest, .oldestToNewest, .shortestToLongest, .longestToShortest, .dragAndDrop]
        let searches: [String?] = [nil, "episode", "O'Brien 100%"]

        for flag in [true, false] {
            featureFlagMock.set(.optimizeManualPlaylistQueries, value: flag)
            for sort in sorts {
                for shouldShowArchived in [false, true] {
                    for search in searches {
                        for limit in [0, 4] {
                            let config = "manual flag=\(flag) sort=\(sort) archived=\(shouldShowArchived) search=\(search ?? "nil") limit=\(limit)"

                            let episodeRows = assertEpisodeParity(
                                clause: .episode, selection: .episodes,
                                playlist: manualPlaylist, episodeUuidToAdd: nil,
                                searchTerm: search, limit: limit,
                                shouldShowArchived: shouldShowArchived, sortType: sort,
                                "episode \(config)"
                            )
                            if search == nil, limit == 0 {
                                XCTAssertFalse(episodeRows.isEmpty, "Sanity: manual episode rows should not be empty for \(config)")
                            }

                            let distinctRows = assertEpisodeParity(
                                clause: .firstDistinctEpisodes, selection: .firstDistinctEpisodes,
                                playlist: manualPlaylist, episodeUuidToAdd: nil,
                                searchTerm: search, limit: limit,
                                shouldShowArchived: shouldShowArchived, sortType: sort,
                                "firstDistinct \(config)"
                            )
                            if search == nil, limit == 4 {
                                XCTAssertFalse(distinctRows.isEmpty, "Sanity: manual first-distinct rows should not be empty for \(config)")
                            }
                        }
                    }
                }
            }
        }
    }

    func testManualCountParityMatrix() {
        // Search terms are part of the matrix deliberately: with the optimization
        // flag on the legacy builder appends the search predicate to count queries,
        // with it off the early-returned count SQL ignores the search term entirely.
        // Both quirks must reproduce.
        let searches: [String?] = [nil, "episode"]

        for flag in [true, false] {
            featureFlagMock.set(.optimizeManualPlaylistQueries, value: flag)
            for shouldShowArchived in [false, true] {
                for search in searches {
                    let config = "manual flag=\(flag) archived=\(shouldShowArchived) search=\(search ?? "nil")"

                    let count = assertCountParity(
                        clause: .episodeCount, selection: .episodeCount,
                        playlist: manualPlaylist, episodeUuidToAdd: nil,
                        searchTerm: search, shouldShowArchived: shouldShowArchived,
                        "episodeCount \(config)"
                    )
                    if search == nil, !shouldShowArchived {
                        XCTAssertGreaterThan(count, 0, "Sanity: manual episodeCount should be positive for \(config)")
                    }

                    assertCountParity(
                        clause: .allEpisodeCount, selection: .allEpisodeCount,
                        playlist: manualPlaylist, episodeUuidToAdd: nil,
                        searchTerm: search, shouldShowArchived: shouldShowArchived,
                        "allEpisodeCount \(config)"
                    )
                }
            }
        }
    }

    // MARK: - Smart playlists

    func testSmartEpisodeParityMatrix() {
        let sorts: [PlaylistSort] = [.newestToOldest, .shortestToLongest]
        let searches: [String?] = [nil, "O'Brien 100%"]

        for (name, playlist) in smartFixtures() {
            for episodeUuidToAdd in [nil, pinnedEpisodeUuid] {
                for shouldShowArchived in [false, true] {
                    for search in searches {
                        for sort in sorts {
                            let config = "smart=\(name) uuidToAdd=\(episodeUuidToAdd ?? "nil") archived=\(shouldShowArchived) search=\(search ?? "nil") sort=\(sort)"

                            let rows = assertEpisodeParity(
                                clause: .episode, selection: .episodes,
                                playlist: playlist, episodeUuidToAdd: episodeUuidToAdd,
                                searchTerm: search, limit: 0,
                                shouldShowArchived: shouldShowArchived, sortType: sort,
                                "episode \(config)"
                            )
                            // Every fixture matches at least one non-archived episode.
                            if episodeUuidToAdd == nil, !shouldShowArchived, search == nil {
                                XCTAssertFalse(rows.isEmpty, "Sanity: smart episode rows should not be empty for \(config)")
                            }

                            assertEpisodeParity(
                                clause: .firstDistinctEpisodes, selection: .firstDistinctEpisodes,
                                playlist: playlist, episodeUuidToAdd: episodeUuidToAdd,
                                searchTerm: search, limit: 4,
                                shouldShowArchived: shouldShowArchived, sortType: sort,
                                "firstDistinct \(config)"
                            )
                        }
                    }
                }
            }
        }
    }

    func testSmartEpisodeParityWithLimit() {
        for (name, playlist) in smartFixtures() {
            for limit in [0, 2] {
                assertEpisodeParity(
                    clause: .episode, selection: .episodes,
                    playlist: playlist, episodeUuidToAdd: nil,
                    searchTerm: nil, limit: limit,
                    shouldShowArchived: false, sortType: .newestToOldest,
                    "episode smart=\(name) limit=\(limit)"
                )
            }
        }
    }

    func testSmartCountParityMatrix() {
        for (name, playlist) in smartFixtures() {
            for episodeUuidToAdd in [nil, pinnedEpisodeUuid] {
                for shouldShowArchived in [false, true] {
                    let config = "smart=\(name) uuidToAdd=\(episodeUuidToAdd ?? "nil") archived=\(shouldShowArchived)"

                    let count = assertCountParity(
                        clause: .episodeCount, selection: .episodeCount,
                        playlist: playlist, episodeUuidToAdd: episodeUuidToAdd,
                        searchTerm: nil, shouldShowArchived: shouldShowArchived,
                        "episodeCount \(config)"
                    )
                    if episodeUuidToAdd == nil, !shouldShowArchived {
                        XCTAssertGreaterThan(count, 0, "Sanity: smart episodeCount should be positive for \(config)")
                    }

                    assertCountParity(
                        clause: .allEpisodeCount, selection: .allEpisodeCount,
                        playlist: playlist, episodeUuidToAdd: episodeUuidToAdd,
                        searchTerm: nil, shouldShowArchived: shouldShowArchived,
                        "allEpisodeCount \(config)"
                    )
                }
            }
        }
    }

    /// The truly-empty rule set (no smart rules at all AND no unsubscribed podcasts)
    /// exercises the legacy `removeEmptyFilterGroups` regex path against the typed
    /// builder's structural empty-fragment handling, including the `OR (1)` rewrite
    /// when an `episodeUuidToAdd` arm is present.
    func testEmptyRuleGroupParityWithNoUnsubscribedPodcasts() {
        // Resubscribe podcast C so the NOT IN rule disappears from both builders.
        var resubscribed = podcastC!
        resubscribed.subscribed = 1
        resubscribed = dataManager.save(podcast: resubscribed)
        defer {
            var back = resubscribed
            back.subscribed = 0
            dataManager.save(podcast: back)
        }

        var playlist = EpisodeFilter()
        playlist.manual = false
        playlist.uuid = "smart-truly-empty"
        // Neutralize the implicit always-true filterDownloading rule
        playlist.filterDownloaded = true
        playlist.filterNotDownloaded = true

        for episodeUuidToAdd in [nil, pinnedEpisodeUuid] {
            let config = "emptyRules uuidToAdd=\(episodeUuidToAdd ?? "nil")"

            let rows = assertEpisodeParity(
                clause: .episode, selection: .episodes,
                playlist: playlist, episodeUuidToAdd: episodeUuidToAdd,
                searchTerm: nil, limit: 0,
                shouldShowArchived: false, sortType: .newestToOldest,
                "episode \(config)"
            )
            XCTAssertFalse(rows.isEmpty, "Sanity: empty-rule playlist should match episodes for \(config)")
            XCTAssertTrue(rows.contains { $0.uuid == "ep-c1" }, "Sanity: resubscribed podcast episode should match for \(config)")

            assertEpisodeParity(
                clause: .firstDistinctEpisodes, selection: .firstDistinctEpisodes,
                playlist: playlist, episodeUuidToAdd: episodeUuidToAdd,
                searchTerm: nil, limit: 4,
                shouldShowArchived: false, sortType: .newestToOldest,
                "firstDistinct \(config)"
            )

            assertCountParity(
                clause: .episodeCount, selection: .episodeCount,
                playlist: playlist, episodeUuidToAdd: episodeUuidToAdd,
                searchTerm: nil, shouldShowArchived: false,
                "episodeCount \(config)"
            )
        }
    }

    /// Legacy quirk, pinned: a smart playlist sorted by drag-and-drop emits
    /// `ORDER BY p.pos` with no `p` alias in scope, so the query fails at runtime
    /// and both implementations surface zero rows through the error-swallowing
    /// fetch paths.
    func testSmartPlaylistDragAndDropSortQuirkPreserved() {
        var playlist = EpisodeFilter()
        playlist.manual = false
        playlist.uuid = "smart-drag"
        playlist.filterUnplayed = true

        let legacy = legacyEpisodes(clause: .episode, playlist: playlist, episodeUuidToAdd: nil, searchTerm: nil, limit: 0, shouldShowArchived: false, sortType: .dragAndDrop)
        let typed = typedEpisodes(selection: .episodes, playlist: playlist, episodeUuidToAdd: nil, searchTerm: nil, limit: 0, shouldShowArchived: false, sortType: .dragAndDrop)

        XCTAssertTrue(legacy.isEmpty, "Legacy smart drag-and-drop query should fail and yield no rows")
        XCTAssertTrue(typed.isEmpty, "Typed smart drag-and-drop query should reproduce the legacy failure shape")
    }

    // MARK: - queryFor / filterEpisodesRequest

    func testFilterEpisodesRequestParityMatrix() {
        for (name, fixture) in smartFixtures() {
            for sortType in [PlaylistSort.newestToOldest, .oldestToNewest, .shortestToLongest, .longestToShortest] {
                var playlist = fixture
                playlist.sortType = sortType.rawValue
                for episodeUuidToAdd in [nil, pinnedEpisodeUuid] {
                    for limit in [0, 3] {
                        let config = "queryFor smart=\(name) sort=\(sortType) uuidToAdd=\(episodeUuidToAdd ?? "nil") limit=\(limit)"

                        let query = PlaylistQueryBuilder.queryFor(filter: playlist, episodeUuidToAdd: episodeUuidToAdd, limit: limit)
                        let legacy = dataManager.findEpisodesWhere(customWhere: query.sql, arguments: query.arguments)

                        let request = PlaylistQueryBuilder.filterEpisodesRequest(for: playlist, episodeUuidToAdd: episodeUuidToAdd, limit: limit)
                        let typed = dataManager.episodes(matching: request)

                        XCTAssertEqual(legacy.map(\.id), typed.map(\.id), "Episode id order mismatch: \(config)")
                        XCTAssertEqual(legacy.map(\.uuid), typed.map(\.uuid), "Episode uuid order mismatch: \(config)")
                        if episodeUuidToAdd == nil, limit == 0 {
                            XCTAssertFalse(legacy.isEmpty, "Sanity: queryFor rows should not be empty for \(config)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - podcastExistsInPlaylistEpisodes

    func testPodcastExistsParity() throws {
        // Seed a playlist row for a podcast and then soft-delete it, to cover the
        // wasDeleted branch.
        var deletedGhost = Episode()
        deletedGhost.uuid = "ghost-deleted"
        deletedGhost.podcastUuid = "podcast-deleted"
        XCTAssertTrue(dataManager.add(episodes: [deletedGhost], to: manualPlaylist))
        dataManager.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE \(DataManager.playlistEpisodeTableName) SET wasDeleted = 1 WHERE podcastUuid = ?",
                arguments: ["podcast-deleted"]
            )
        }

        for podcastUuid in ["podcast-a", "podcast-none", "podcast-deleted"] {
            for includeDeleted in [false, true] {
                let config = "podcastExists uuid=\(podcastUuid) includeDeleted=\(includeDeleted)"

                let legacySql = PlaylistQueryBuilder.podcastExistsInPlaylistEpisodesQuery(includeDeleted: includeDeleted)
                let legacyExists = dataManager.count(query: legacySql, values: [podcastUuid]) == 1

                let request = PlaylistQueryBuilder.podcastExistsInPlaylistEpisodesRequest(podcastUuid: podcastUuid, includeDeleted: includeDeleted)
                let typedExists = dataManager.exists(matching: request)

                XCTAssertEqual(legacyExists, typedExists, "Existence mismatch: \(config)")
            }
        }

        // Direction checks so parity can't pass on inverted logic
        XCTAssertTrue(dataManager.exists(matching: PlaylistQueryBuilder.podcastExistsInPlaylistEpisodesRequest(podcastUuid: "podcast-a")))
        XCTAssertFalse(dataManager.exists(matching: PlaylistQueryBuilder.podcastExistsInPlaylistEpisodesRequest(podcastUuid: "podcast-none")))
        XCTAssertFalse(dataManager.exists(matching: PlaylistQueryBuilder.podcastExistsInPlaylistEpisodesRequest(podcastUuid: "podcast-deleted")))
        XCTAssertTrue(dataManager.exists(matching: PlaylistQueryBuilder.podcastExistsInPlaylistEpisodesRequest(podcastUuid: "podcast-deleted", includeDeleted: true)))
    }

    // MARK: - Consumer-path spot checks

    /// The migrated DataManager conveniences must agree with the legacy strings too
    /// (they now route through the typed requests internally).
    func testDataManagerPlaylistEpisodeFetchesMatchLegacy() {
        for flag in [true, false] {
            featureFlagMock.set(.optimizeManualPlaylistQueries, value: flag)

            let legacyList = legacyEpisodes(clause: .episode, playlist: manualPlaylist, episodeUuidToAdd: nil, searchTerm: nil, limit: 500, shouldShowArchived: false, sortType: nil)
            let viaDataManager = dataManager.playlistEpisodes(for: manualPlaylist, limit: 500)
            XCTAssertEqual(legacyList.map(\.id), viaDataManager.map(\.id), "playlistEpisodes(for:) should match the legacy rows (flag=\(flag))")

            let legacyDistinct = legacyEpisodes(clause: .firstDistinctEpisodes, playlist: manualPlaylist, episodeUuidToAdd: nil, searchTerm: nil, limit: 4, shouldShowArchived: false, sortType: nil)
            let viaDistinct = dataManager.playlistFirstDistinctEpisodes(for: manualPlaylist)
            XCTAssertEqual(legacyDistinct.map(\.id), viaDistinct.map(\.id), "playlistFirstDistinctEpisodes(for:) should match the legacy rows (flag=\(flag))")

            let legacyCountQuery = PlaylistQueryBuilder.query(clause: .episodeCount, for: manualPlaylist, episodeUuidToAdd: nil, shouldShowArchived: false)
            let legacyCount = dataManager.count(query: legacyCountQuery.sql, values: legacyCountQuery.arguments)
            XCTAssertEqual(legacyCount, dataManager.playlistEpisodeCount(for: manualPlaylist, episodeUuidToAdd: nil), "playlistEpisodeCount(for:) should match the legacy count (flag=\(flag))")
        }
    }
}
