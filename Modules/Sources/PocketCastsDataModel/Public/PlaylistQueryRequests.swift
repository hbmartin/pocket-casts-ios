import Foundation
import GRDB
import PocketCastsUtils

/// Typed GRDB counterparts of the legacy string-assembled playlist queries in
/// `PlaylistQueryBuilder.swift`.
///
/// `fragment(clause:for:...)` is the single source of truth for the SQL shape.
/// Values (playlist uuids, search patterns, status raw values, limits) travel as
/// bound arguments via `SQL` interpolation instead of `[Any]` argument arrays and
/// string splices, and the legacy `removeEmptyFilterGroups` regex pass is replaced
/// by structural composition: empty rule groups are never emitted in the first
/// place (`combinedRuleFragment`).
///
/// The legacy `query(clause:...)`/`queryFor(filter:...)` string builders remain as
/// the golden reference: `PlaylistQueryBuilderParityTests` asserts row-set parity
/// between both implementations across the full configuration matrix on a seeded
/// database. Behavioral quirks of the legacy builder (e.g. smart playlists with a
/// drag-and-drop sort emit an `ORDER BY p.pos` that fails at runtime, and manual
/// count queries ignore search terms when `optimizeManualPlaylistQueries` is
/// disabled) are intentionally reproduced, not fixed.
public extension PlaylistQueryBuilder {

    // MARK: - Public typed requests

    /// Episode-returning selections (`SelectClause.episode` / `.firstDistinctEpisodes`).
    enum EpisodeSelection: Sendable {
        case episodes
        case firstDistinctEpisodes
    }

    /// Count-returning selections (`SelectClause.episodeCount` / `.allEpisodeCount`).
    enum CountSelection: Sendable {
        case episodeCount
        case allEpisodeCount
    }

    /// Typed twin of `query(clause:for:...)` for the episode-returning clauses.
    static func episodesRequest(
        _ selection: EpisodeSelection = .episodes,
        for playlist: EpisodeFilter,
        episodeUuidToAdd: String? = nil,
        searchTerm: String? = nil,
        limit: Int = 0,
        shouldShowArchived: Bool = false,
        sortType: PlaylistSort? = nil
    ) -> SQLRequest<Episode> {
        let clause: SelectClause
        switch selection {
        case .episodes: clause = .episode
        case .firstDistinctEpisodes: clause = .firstDistinctEpisodes
        }
        return SQLRequest(literal: fragment(
            clause: clause,
            for: playlist,
            episodeUuidToAdd: episodeUuidToAdd,
            searchTerm: searchTerm,
            limit: limit,
            shouldShowArchived: shouldShowArchived,
            sortType: sortType
        ))
    }

    /// Typed twin of `query(clause:for:...)` for the count clauses.
    static func countRequest(
        _ selection: CountSelection,
        for playlist: EpisodeFilter,
        episodeUuidToAdd: String? = nil,
        searchTerm: String? = nil,
        limit: Int = 0,
        shouldShowArchived: Bool = false
    ) -> SQLRequest<Int> {
        let clause: SelectClause
        switch selection {
        case .episodeCount: clause = .episodeCount
        case .allEpisodeCount: clause = .allEpisodeCount
        }
        return SQLRequest(literal: fragment(
            clause: clause,
            for: playlist,
            episodeUuidToAdd: episodeUuidToAdd,
            searchTerm: searchTerm,
            limit: limit,
            shouldShowArchived: shouldShowArchived,
            sortType: nil
        ))
    }

    /// Typed twin of the legacy `queryFor(filter:episodeUuidToAdd:limit:)` WHERE-fragment
    /// API: a single-table, unqualified filter query over `SJEpisode` (no podcast join,
    /// no archived toggle beyond `archived = 0`). Used by widgets, playback intents and
    /// the filter episode lists.
    static func filterEpisodesRequest(
        for filter: EpisodeFilter,
        episodeUuidToAdd: String?,
        limit: Int
    ) -> SQLRequest<Episode> {
        var query: SQL = "SELECT * FROM \(sql: DataManager.episodeTableName) WHERE archived = 0"

        let rules = smartRuleFragments(for: filter, prefix: "")
        query = query + combinedRuleFragment(rules: rules, episodeUuidToAdd: episodeUuidToAdd, prefix: "")

        // The legacy builder only sorts on the four explicit sort types here (no
        // drag-and-drop mapping for the fragment API).
        if filter.sortType == PlaylistSort.oldestToNewest.rawValue {
            query = query + " ORDER BY publishedDate ASC, addedDate ASC"
        } else if filter.sortType == PlaylistSort.newestToOldest.rawValue {
            query = query + " ORDER BY publishedDate DESC, addedDate DESC"
        } else if filter.sortType == PlaylistSort.shortestToLongest.rawValue {
            query = query + " ORDER BY duration ASC, addedDate ASC"
        } else if filter.sortType == PlaylistSort.longestToShortest.rawValue {
            query = query + " ORDER BY duration DESC, addedDate DESC"
        }

        if limit > 0 {
            query = query + " LIMIT \(limit)"
        }

        return SQLRequest(literal: query)
    }

    /// Typed twin of `podcastExistsInPlaylistEpisodesQuery(includeDeleted:)`, with the
    /// podcast uuid bound in. Fetches one row (`1`) when the podcast appears in any
    /// playlist episode, or no row otherwise.
    static func podcastExistsInPlaylistEpisodesRequest(
        podcastUuid: String,
        includeDeleted: Bool = false
    ) -> SQLRequest<Int> {
        var query: SQL = "SELECT 1 FROM \(sql: DataManager.playlistEpisodeTableName) WHERE podcastUuid = \(podcastUuid)"
        if !includeDeleted {
            query = query + " AND wasDeleted = 0"
        }
        query = query + " LIMIT 1"
        return SQLRequest(literal: query)
    }
}

// MARK: - Fragment builder (single source of truth)

extension PlaylistQueryBuilder {

    /// Builds the full SQL fragment for a clause, mirroring the legacy
    /// `query(clause:for:...)` assembly branch by branch.
    static func fragment(
        clause: SelectClause,
        for playlist: EpisodeFilter,
        episodeUuidToAdd: String?,
        searchTerm: String?,
        limit: Int,
        shouldShowArchived: Bool,
        sortType: PlaylistSort?
    ) -> SQL {
        let sortType = sortType?.rawValue ?? playlist.sortType

        var query: SQL = ""
        // Mirrors the legacy flag: it starts true and only the manual `.episode`
        // branch updates it, so count clauses append search terms with `AND` even
        // when their SQL has no WHERE (a legacy quirk preserved for parity; real
        // callers never pass search terms to count clauses).
        var mainQueryHasWhere = true

        if playlist.manual {
            switch clause {
            case .episode:
                query = manualEpisodesFragment(playlistUuid: playlist.uuid, shouldShowArchived: shouldShowArchived)
                mainQueryHasWhere = !shouldShowArchived
            case .episodeCount:
                if FeatureFlag.optimizeManualPlaylistQueries.enabled {
                    query = manualCountFragment(playlistUuid: playlist.uuid, shouldShowArchived: shouldShowArchived, allEpisodesCount: false)
                } else {
                    // Early return, like the legacy builder: search term and limit are ignored.
                    return manualLegacyCountFragment(playlistUuid: playlist.uuid, shouldShowArchived: shouldShowArchived, allEpisodesCount: false)
                }
            case .allEpisodeCount:
                if FeatureFlag.optimizeManualPlaylistQueries.enabled {
                    query = manualCountFragment(playlistUuid: playlist.uuid, shouldShowArchived: shouldShowArchived, allEpisodesCount: true)
                } else {
                    return manualLegacyCountFragment(playlistUuid: playlist.uuid, shouldShowArchived: shouldShowArchived, allEpisodesCount: true)
                }
            case .firstDistinctEpisodes:
                return manualFirstDistinctFragment(
                    sortType: sortType,
                    limit: limit,
                    playlistUuid: playlist.uuid,
                    shouldShowArchived: shouldShowArchived,
                    searchTerm: searchTerm
                )
            }
        } else {
            let rules = smartRuleFragments(for: playlist, prefix: "episode.")
            let whereFragment = combinedRuleFragment(rules: rules, episodeUuidToAdd: episodeUuidToAdd, prefix: "episode.")

            switch clause {
            case .firstDistinctEpisodes:
                return smartFirstDistinctFragment(
                    sortType: sortType,
                    limit: limit,
                    whereFragment: whereFragment,
                    searchTerm: searchTerm
                )
            case .episodeCount, .allEpisodeCount:
                return smartCountFragment(
                    shouldShowArchived: shouldShowArchived,
                    allEpisodesCount: clause == .allEpisodeCount,
                    whereFragment: whereFragment
                )
            case .episode:
                query = "SELECT episode.* FROM \(sql: DataManager.episodeTableName) episode LEFT JOIN \(sql: DataManager.podcastTableName) podcast ON episode.podcast_id = podcast.id WHERE episode.archived = 0\(whereFragment)"
            }
        }

        if let searchTerm {
            let keyword = mainQueryHasWhere ? "AND" : "WHERE"
            query = query + " \(sql: keyword) " + searchGroup(searchTerm)
        }
        if clause != .episodeCount, clause != .allEpisodeCount, let sort = orderByClause(sortType: sortType, prefix: "episode.") {
            query = query + " " + sort
        }
        if limit > 0 {
            query = query + " LIMIT \(limit)"
        }
        return query
    }

    // MARK: Manual playlists

    /// The manual-playlist `.episode` CTE. Deduplicates rows sharing an episode uuid,
    /// preferring (flag on) rows whose archived state matches the displayed state and
    /// that are not downloaded, or (flag off) rows that are not downloaded, then the
    /// lowest row id.
    private static func manualEpisodesFragment(playlistUuid: String, shouldShowArchived: Bool) -> SQL {
        let archivedFilter: SQL = shouldShowArchived ? "" : "WHERE episode.archived = 0"

        if FeatureFlag.optimizeManualPlaylistQueries.enabled {
            let archivedPreference = shouldShowArchived ? 1 : 0
            return """
            WITH playlist AS (
              SELECT episodeUuid, MIN(episodePosition) AS pos
              FROM \(sql: DataManager.playlistEpisodeTableName)
              WHERE playlist_uuid = \(playlistUuid)
              GROUP BY episodeUuid
            ),
            deduped_episode AS (
              SELECT episode.*,
                     ROW_NUMBER() OVER (
                       PARTITION BY episode.uuid
                       ORDER BY
                         CASE WHEN episode.archived = \(archivedPreference) AND episode.episodeStatus = \(DownloadStatus.notDownloaded.rawValue) THEN 0
                              WHEN episode.archived = \(archivedPreference) THEN 1
                              WHEN episode.episodeStatus = \(DownloadStatus.notDownloaded.rawValue) THEN 2
                              ELSE 3 END,
                         episode.id ASC
                     ) AS rn
              FROM \(sql: DataManager.episodeTableName) episode
              WHERE episode.uuid IN (SELECT episodeUuid FROM playlist)
            )
            SELECT episode.*
            FROM playlist p
            JOIN deduped_episode episode
              ON episode.uuid = p.episodeUuid
              AND episode.rn = 1
            LEFT JOIN \(sql: DataManager.podcastTableName) podcast
              ON episode.podcast_id = podcast.id
            \(archivedFilter)
            """
        }

        // Original query without optimization: the dedupe window scans the whole
        // episode table (no uuid IN (...) pre-filter) and prefers not-downloaded rows.
        return """
        WITH playlist AS (
          SELECT episodeUuid, MIN(episodePosition) AS pos
          FROM \(sql: DataManager.playlistEpisodeTableName)
          WHERE playlist_uuid = \(playlistUuid)
          GROUP BY episodeUuid
        ),
        deduped_episode AS (
          SELECT episode.*,
                 ROW_NUMBER() OVER (
                   PARTITION BY episode.uuid
                   ORDER BY
                     CASE WHEN episode.episodeStatus = \(DownloadStatus.notDownloaded.rawValue) THEN 0 ELSE 1 END,
                     episode.id ASC
                 ) AS rn
          FROM \(sql: DataManager.episodeTableName) episode
        )
        SELECT episode.*
        FROM playlist p
        JOIN deduped_episode episode
          ON episode.uuid = p.episodeUuid
          AND episode.rn = 1
        LEFT JOIN \(sql: DataManager.podcastTableName) podcast
          ON episode.podcast_id = podcast.id
        \(archivedFilter)
        """
    }

    /// Manual-playlist counts with `optimizeManualPlaylistQueries` enabled.
    /// `.episodeCount` counts rows matching the archived toggle exactly;
    /// `.allEpisodeCount` counts everything (or non-archived when the toggle is off).
    private static func manualCountFragment(playlistUuid: String, shouldShowArchived: Bool, allEpisodesCount: Bool) -> SQL {
        let whereClause: SQL = allEpisodesCount
            ? (shouldShowArchived ? "" : "WHERE episode.archived = 0")
            : "WHERE episode.archived = \(sql: shouldShowArchived ? "1" : "0")"

        return """
        WITH playlist AS (
          SELECT episodeUuid, MIN(episodePosition) AS pos
          FROM \(sql: DataManager.playlistEpisodeTableName)
          WHERE playlist_uuid = \(playlistUuid)
          GROUP BY episodeUuid
        ),
        deduped_episode AS (
          SELECT episode.*,
                 ROW_NUMBER() OVER (
                   PARTITION BY episode.uuid
                   ORDER BY
                     CASE WHEN episode.episodeStatus = \(DownloadStatus.notDownloaded.rawValue) THEN 0 ELSE 1 END,
                     episode.id ASC
                 ) AS rn
          FROM \(sql: DataManager.episodeTableName) episode
          WHERE episode.uuid IN (SELECT episodeUuid FROM playlist)
        )
        SELECT COUNT(*)
        FROM playlist p
        JOIN deduped_episode episode
          ON episode.uuid = p.episodeUuid
          AND episode.rn = 1
        LEFT JOIN \(sql: DataManager.podcastTableName) podcast
          ON episode.podcast_id = podcast.id
        \(whereClause)
        """
    }

    /// Manual-playlist counts with `optimizeManualPlaylistQueries` disabled
    /// (legacy `manualPlaylistEpisodesCount`).
    private static func manualLegacyCountFragment(playlistUuid: String, shouldShowArchived: Bool, allEpisodesCount: Bool) -> SQL {
        let whereClause: SQL = allEpisodesCount
            ? (shouldShowArchived ? "WHERE t.rn = 1" : "WHERE t.rn = 1 AND t.archived = 0")
            : "WHERE t.rn = 1 AND t.archived = \(sql: shouldShowArchived ? "1" : "0")"

        return """
        WITH playlist AS (
          SELECT episodeUuid
          FROM \(sql: DataManager.playlistEpisodeTableName)
          WHERE playlist_uuid = \(playlistUuid)
          GROUP BY episodeUuid
        ),
        deduped_uuid AS (
          SELECT uuid
          FROM (
            SELECT episode.uuid AS uuid,
                   episode.archived AS archived,
                   ROW_NUMBER() OVER (
                     PARTITION BY episode.uuid
                     ORDER BY
                       CASE WHEN episode.episodeStatus = \(DownloadStatus.notDownloaded.rawValue) THEN 0 ELSE 1 END,
                       episode.id ASC
                   ) AS rn
            FROM \(sql: DataManager.episodeTableName) episode
          ) t
          \(whereClause)
        )
        SELECT COUNT(*)
        FROM playlist p
        JOIN deduped_uuid d
          ON d.uuid = p.episodeUuid
        """
    }

    /// Legacy `manualPlaylistFirstDistinctEpisodes`: first episode per podcast within a
    /// manual playlist, in four variants (custom order x optimization flag).
    private static func manualFirstDistinctFragment(
        sortType: Int32,
        limit: Int,
        playlistUuid: String,
        shouldShowArchived: Bool,
        searchTerm: String?
    ) -> SQL {
        let isCustomOrderSortType = sortType == PlaylistSort.dragAndDrop.rawValue

        var playlistPositionOrderBy: SQL = "ORDER BY playlist_position ASC"
        var episodePositionOrderByStripped: SQL = "ORDER BY playlist.episodePosition ASC"
        if !isCustomOrderSortType {
            if let sortByPlaylist = orderByClause(sortType: sortType, prefix: "") {
                playlistPositionOrderBy = sortByPlaylist
                episodePositionOrderByStripped = sortByPlaylist
            }
        }

        let archivedPredicateForDeduped: SQL = shouldShowArchived ? "" : "AND de.archived = 0"
        let archivedPredicateForEpisode: SQL = shouldShowArchived ? "" : "AND episode.archived = 0"
        let archivedPreference = shouldShowArchived ? 1 : 0
        var searchPredicate: SQL = ""
        var podcastSearchJoin: SQL = ""
        if let searchTerm {
            searchPredicate = "AND \(searchGroup(searchTerm))"
            podcastSearchJoin = "LEFT JOIN \(sql: DataManager.podcastTableName) podcast ON episode.podcast_id = podcast.id"
        }

        if isCustomOrderSortType {
            if FeatureFlag.optimizeManualPlaylistQueries.enabled {
                return """
                WITH playlist AS (
                  SELECT episodeUuid, MIN(episodePosition) AS episodePosition
                  FROM \(sql: DataManager.playlistEpisodeTableName)
                  WHERE playlist_uuid = \(playlistUuid)
                  GROUP BY episodeUuid
                ),
                deduped_episode AS (
                  SELECT episode.*,
                         ROW_NUMBER() OVER (
                           PARTITION BY episode.uuid
                           ORDER BY
                             CASE WHEN episode.archived = \(archivedPreference) AND episode.episodeStatus = \(DownloadStatus.notDownloaded.rawValue) THEN 0
                                  WHEN episode.archived = \(archivedPreference) THEN 1
                                  WHEN episode.episodeStatus = \(DownloadStatus.notDownloaded.rawValue) THEN 2
                                  ELSE 3 END,
                             episode.id ASC
                         ) AS uuid_rn
                  FROM \(sql: DataManager.episodeTableName) episode
                  \(podcastSearchJoin)
                  WHERE episode.uuid IN (SELECT episodeUuid FROM playlist)
                  \(searchPredicate)
                ),
                playlist_rows AS (
                  SELECT de.id,
                         de.podcast_id,
                         p.episodePosition AS playlist_position
                  FROM deduped_episode de
                  JOIN playlist p
                    ON de.uuid = p.episodeUuid
                  WHERE de.uuid_rn = 1
                  \(archivedPredicateForDeduped)
                  LIMIT \(episodeLimit)
                ),
                first_per_podcast AS (
                  SELECT podcast_id, MIN(playlist_position) AS min_pos
                  FROM playlist_rows
                  GROUP BY podcast_id
                ),
                chosen_ids AS (
                  SELECT pr.id, pr.playlist_position
                  FROM playlist_rows pr
                  JOIN first_per_podcast f
                    ON pr.podcast_id = f.podcast_id
                   AND pr.playlist_position = f.min_pos
                )
                SELECT episode.*
                FROM \(sql: DataManager.episodeTableName) episode
                JOIN chosen_ids c
                  ON episode.id = c.id
                ORDER BY c.playlist_position ASC
                LIMIT \(limit)
                """
            }

            // Original query without deduplication
            return """
            WITH playlist_rows AS (
              SELECT episode.id,
                     episode.podcast_id,
                     playlist.episodePosition AS playlist_position
              FROM \(sql: DataManager.episodeTableName) episode
              JOIN \(sql: DataManager.playlistEpisodeTableName) playlist
                ON episode.uuid = playlist.episodeUuid
              \(podcastSearchJoin)
              WHERE playlist.playlist_uuid = \(playlistUuid)
              \(archivedPredicateForEpisode)
              \(searchPredicate)
              LIMIT \(episodeLimit)
            ),
            first_per_podcast AS (
              SELECT podcast_id, MIN(playlist_position) AS min_pos
              FROM playlist_rows
              GROUP BY podcast_id
            ),
            chosen_ids AS (
              SELECT pr.id, pr.playlist_position
              FROM playlist_rows pr
              JOIN first_per_podcast f
                ON pr.podcast_id = f.podcast_id
               AND pr.playlist_position = f.min_pos
            )
            SELECT episode.*
            FROM \(sql: DataManager.episodeTableName) episode
            JOIN chosen_ids c
              ON episode.id = c.id
            ORDER BY c.playlist_position ASC
            LIMIT \(limit)
            """
        }

        if FeatureFlag.optimizeManualPlaylistQueries.enabled {
            // Optimized version: deduplicates by UUID first, then partitions by podcast.
            // The legacy dedupe CASE here hardcodes episodeStatus = 1 (notDownloaded).
            return """
            WITH playlist AS (
              SELECT episodeUuid, MIN(episodePosition) AS episodePosition
              FROM \(sql: DataManager.playlistEpisodeTableName)
              WHERE playlist_uuid = \(playlistUuid)
              GROUP BY episodeUuid
            ),
            deduped_episode AS (
              SELECT episode.*,
                     ROW_NUMBER() OVER (
                       PARTITION BY episode.uuid
                       ORDER BY
                         CASE WHEN episode.archived = \(archivedPreference) AND episode.episodeStatus = \(DownloadStatus.notDownloaded.rawValue) THEN 0
                              WHEN episode.archived = \(archivedPreference) THEN 1
                              WHEN episode.episodeStatus = \(DownloadStatus.notDownloaded.rawValue) THEN 2
                              ELSE 3 END,
                         episode.id ASC
                     ) AS uuid_rn
              FROM \(sql: DataManager.episodeTableName) episode
              \(podcastSearchJoin)
              WHERE episode.uuid IN (SELECT episodeUuid FROM playlist)
              \(searchPredicate)
            ),
            ordered_episodes AS (
              SELECT de.id,
                     de.podcast_id,
                     p.episodePosition AS playlist_position,
                     ROW_NUMBER() OVER (
                       PARTITION BY de.podcast_id
                       \(episodePositionOrderByStripped)
                     ) AS podcast_rn
              FROM deduped_episode de
              JOIN playlist p
                ON de.uuid = p.episodeUuid
              WHERE de.uuid_rn = 1
              \(archivedPredicateForDeduped)
              LIMIT \(episodeLimit)
            )
            SELECT episode.*
            FROM ordered_episodes oe
            JOIN \(sql: DataManager.episodeTableName) episode
              ON episode.id = oe.id
            WHERE oe.podcast_rn = 1
            \(playlistPositionOrderBy)
            LIMIT \(limit)
            """
        }

        return """
        WITH ordered_episodes AS (
          SELECT episode.id,
                 episode.podcast_id,
                 playlist.episodePosition AS playlist_position,
                 episode.publishedDate,
                 episode.addedDate,
                 episode.duration
          FROM \(sql: DataManager.episodeTableName) episode
          JOIN \(sql: DataManager.playlistEpisodeTableName) playlist
            ON episode.uuid = playlist.episodeUuid
          \(podcastSearchJoin)
          WHERE playlist.playlist_uuid = \(playlistUuid)
          \(archivedPredicateForEpisode)
          \(searchPredicate)
          LIMIT \(episodeLimit)
        ),
        numbered AS (
          SELECT *,
                 ROW_NUMBER() OVER (
                   PARTITION BY podcast_id
                   \(episodePositionOrderByStripped)
                 ) AS rn
          FROM ordered_episodes
        )
        SELECT episode.*
        FROM numbered n
        JOIN \(sql: DataManager.episodeTableName) episode
          ON episode.id = n.id
        WHERE n.rn = 1
        \(playlistPositionOrderBy)
        LIMIT \(limit)
        """
    }

    // MARK: Smart playlists

    /// Legacy `smartPlaylistFirstDistinctEpisodes`: first matching episode per podcast,
    /// bounded to `episodeLimit` candidate rows.
    private static func smartFirstDistinctFragment(
        sortType: Int32,
        limit: Int,
        whereFragment: SQL,
        searchTerm: String?
    ) -> SQL {
        let sortClause: SQL = orderByClause(sortType: sortType, prefix: "episode.") ?? ""
        let sortClauseStripped: SQL = orderingTerms(sortType: sortType, prefix: "") ?? ""
        var searchPredicate: SQL = ""
        if let searchTerm {
            searchPredicate = "AND \(searchGroup(searchTerm))"
        }

        return """
        WITH limited_episodes AS (
            SELECT * FROM (
                SELECT episode.id,
                       episode.podcast_id,
                       episode.publishedDate,
                       episode.addedDate,
                       episode.duration
                FROM \(sql: DataManager.episodeTableName) episode
                LEFT JOIN \(sql: DataManager.podcastTableName) podcast
                  ON episode.podcast_id = podcast.id
                WHERE episode.archived = 0\(whereFragment)
                \(searchPredicate)
                \(sortClause)
                LIMIT \(episodeLimit)
            )
        ),
        numbered_episodes AS (
            SELECT *,
                   ROW_NUMBER() OVER (
                       PARTITION BY podcast_id
                       ORDER BY \(sortClauseStripped)
                   ) AS rn
            FROM limited_episodes
        )
        SELECT episode.*
        FROM numbered_episodes ne
        JOIN \(sql: DataManager.episodeTableName) episode
          ON episode.id = ne.id
        WHERE ne.rn = 1
        ORDER BY \(sortClauseStripped)
        LIMIT \(limit)
        """
    }

    /// Legacy `smartPlaylistEpisodesCount`: counts distinct episode uuids matching the
    /// smart rules, deduplicated the same way as the episode listing.
    private static func smartCountFragment(
        shouldShowArchived: Bool,
        allEpisodesCount: Bool,
        whereFragment: SQL
    ) -> SQL {
        let whereArchived: SQL = allEpisodesCount
            ? (shouldShowArchived ? "" : " AND episode.archived = 0")
            : " AND episode.archived = \(sql: shouldShowArchived ? "1" : "0")"

        return """
        WITH filtered AS (
          SELECT episode.uuid,
                 episode.archived,
                 episode.episodeStatus,
                 episode.id
          FROM \(sql: DataManager.episodeTableName) episode
          LEFT JOIN \(sql: DataManager.podcastTableName) podcast
            ON episode.podcast_id = podcast.id
          WHERE 1 = 1\(whereArchived)\(whereFragment)
        ),
        deduped AS (
          SELECT uuid
          FROM (
            SELECT f.uuid,
                   ROW_NUMBER() OVER (
                     PARTITION BY f.uuid
                     ORDER BY
                       CASE WHEN f.episodeStatus = \(DownloadStatus.notDownloaded.rawValue) THEN 0 ELSE 1 END,
                       f.id ASC
                   ) AS rn
            FROM filtered f
          ) t
          WHERE rn = 1
        )
        SELECT COUNT(*) FROM deduped
        """
    }

    // MARK: Smart rules

    /// One SQL fragment per active smart rule, in the legacy evaluation order.
    /// `prefix` is `"episode."` for the joined queries and `""` for the
    /// single-table `filterEpisodesRequest`.
    private static func smartRuleFragments(for playlist: EpisodeFilter, prefix: String) -> [SQL] {
        var rules = [SQL]()

        // Playing status: skipped when none or all statuses are selected
        if !(playlist.filterUnplayed && playlist.filterPartiallyPlayed && playlist.filterFinished),
           playlist.filterUnplayed || playlist.filterPartiallyPlayed || playlist.filterFinished {
            var statuses = [SQL]()
            if playlist.filterUnplayed {
                statuses.append("\(sql: prefix)playingStatus = \(PlayingStatus.notPlayed.rawValue)")
            }
            if playlist.filterPartiallyPlayed {
                statuses.append("\(sql: prefix)playingStatus = \(PlayingStatus.inProgress.rawValue)")
            }
            if playlist.filterFinished {
                statuses.append("\(sql: prefix)playingStatus = \(PlayingStatus.completed.rawValue)")
            }
            rules.append("(\(statuses.joined(separator: " OR ")))")
        }

        // Audio / video
        if playlist.filterAudioVideoType == AudioVideoFilter.videoOnly.rawValue {
            rules.append("\(sql: prefix)fileType LIKE 'video%'")
        }
        if playlist.filterAudioVideoType == AudioVideoFilter.audioOnly.rawValue {
            rules.append("\(sql: prefix)fileType LIKE 'audio%'")
        }

        // Download status: skipped when none or all statuses are selected
        if !(playlist.filterDownloaded && playlist.filterDownloading && playlist.filterNotDownloaded),
           playlist.filterDownloaded || playlist.filterDownloading || playlist.filterNotDownloaded {
            var statuses = [SQL]()
            if playlist.filterDownloaded {
                statuses.append("\(sql: prefix)episodeStatus = \(DownloadStatus.downloaded.rawValue)")
            }
            if playlist.filterDownloading {
                statuses.append("\(sql: prefix)episodeStatus = \(DownloadStatus.queued.rawValue)")
                statuses.append("\(sql: prefix)episodeStatus = \(DownloadStatus.downloading.rawValue)")
            }
            if playlist.filterNotDownloaded {
                statuses.append("\(sql: prefix)episodeStatus = \(DownloadStatus.notDownloaded.rawValue)")
                statuses.append("\(sql: prefix)episodeStatus = \(DownloadStatus.downloadFailed.rawValue)")
                statuses.append("\(sql: prefix)episodeStatus = \(DownloadStatus.waitingForWifi.rawValue)")
            }
            rules.append("(\(statuses.joined(separator: " OR ")))")
        }

        // Duration window
        if playlist.filterDuration {
            let longerThanTime = playlist.longerThan * 60
            // we add 59s here to account for how iOS doesn't show "10m" until you get to
            // 10*60 seconds, that way our visual representation lines up with the filter times
            let shorterThanTime = (playlist.shorterThan * 60) + 59
            rules.append("(\(sql: prefix)duration >= \(longerThanTime) AND \(sql: prefix)duration <= \(shorterThanTime))")
        }

        // Starred only
        if playlist.filterStarred {
            rules.append("\(sql: prefix)keepEpisode = 1")
        }

        // Particular podcasts only
        if !playlist.filterAllPodcasts, !playlist.podcastUuids.isEmpty, playlist.podcastUuids != "null" {
            let podcastUuidArr = playlist.podcastUuids.components(separatedBy: ",")
            rules.append("\(sql: prefix)podcastUuid IN \(podcastUuidArr)")
        }

        // Filter out unsubscribed podcasts
        let unsubscribedUuids = DataManager.sharedManager.allUnsubscribedPodcastUuids()
        if !unsubscribedUuids.isEmpty {
            rules.append("\(sql: prefix)podcastUuid NOT IN \(unsubscribedUuids)")
        }

        // Time-based filtering
        if playlist.filterHours > 0 {
            rules.append("\(sql: prefix)publishedDate > \(filterTimeFor(hours: playlist.filterHours))")
        }

        return rules
    }

    /// Structural replacement for the legacy `removeEmptyFilterGroups` regex pass.
    ///
    /// The legacy builder emitted `AND (<rules>)` (or `AND ((uuid = ?) OR (<rules>))`
    /// when keeping the playing episode in the list) and then erased `AND ()` /
    /// rewrote `OR ()` to `OR (1)` with a regex. Building from the rule list makes
    /// those rewrites unnecessary: no rules means no fragment (or a literal `1` in
    /// the OR arm, which keeps the "playing episode stays visible" semantics).
    private static func combinedRuleFragment(rules: [SQL], episodeUuidToAdd: String?, prefix: String) -> SQL {
        let joined = rules.joined(separator: " AND ")
        if let episodeUuidToAdd {
            let ruleArm: SQL = rules.isEmpty ? "1" : joined
            return " AND ((\(sql: prefix)uuid = \(episodeUuidToAdd)) OR (\(ruleArm)))"
        }
        if rules.isEmpty {
            return ""
        }
        return " AND (\(joined))"
    }

    // MARK: Shared pieces

    /// The search predicate group `(UPPER(episode.title) LIKE ? ESCAPE '\' OR
    /// UPPER(podcast.title) LIKE ? ESCAPE '\')`, with the wildcard-escaped pattern
    /// bound in. Callers prepend `AND`/`WHERE` as needed.
    private static func searchGroup(_ searchTerm: String) -> SQL {
        let pattern = likePattern(for: searchTerm)
        return "(UPPER(episode.title) LIKE \(pattern) ESCAPE '\\' OR UPPER(podcast.title) LIKE \(pattern) ESCAPE '\\')"
    }

    /// The ORDER BY terms for a sort type, without the `ORDER BY` keyword.
    /// `prefix` qualifies the columns (`"episode."`) or leaves them bare (`""`),
    /// replacing the legacy `replacingOccurrences(of: "episode.", ...)` stripping.
    private static func orderingTerms(sortType: Int32, prefix: String) -> SQL? {
        guard let sort = PlaylistSort(rawValue: sortType) else {
            return nil
        }
        switch sort {
        case .oldestToNewest:
            return "\(sql: prefix)publishedDate ASC, \(sql: prefix)addedDate ASC"
        case .newestToOldest:
            return "\(sql: prefix)publishedDate DESC, \(sql: prefix)addedDate DESC"
        case .shortestToLongest:
            return "\(sql: prefix)duration ASC, \(sql: prefix)addedDate ASC"
        case .longestToShortest:
            return "\(sql: prefix)duration DESC, \(sql: prefix)addedDate DESC"
        case .dragAndDrop:
            // Only meaningful for manual playlists (the `p` alias is the playlist CTE);
            // like the legacy builder, smart playlists that reach this produce a query
            // that fails at runtime and yields no rows.
            return "p.pos ASC"
        }
    }

    private static func orderByClause(sortType: Int32, prefix: String) -> SQL? {
        orderingTerms(sortType: sortType, prefix: prefix).map { "ORDER BY \($0)" }
    }
}
