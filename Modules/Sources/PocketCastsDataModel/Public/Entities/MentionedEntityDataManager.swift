import Foundation
import GRDB
import PocketCastsUtils

/// Data access for the Mentioned Entity substrate (migration 89, Highlights
/// S10): per-episode+source whole replacement on write, GROUP BY aggregates
/// on read.
public struct MentionedEntityDataManager: Sendable {
    private let dbQueue: GRDBQueue

    init(dbQueue: GRDBQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Writes

    /// Replaces one episode+source's rows whole (regeneration semantics).
    @discardableResult
    public func replace(
        episodeUuid: String,
        source: MentionedEntitySource,
        entities: [MentionedEntityRecord]
    ) -> Bool {
        dbQueue.write { db in
            _ = try MentionedEntityRecord
                .filter(MentionedEntityRecord.Columns.episodeUuid == episodeUuid)
                .filter(MentionedEntityRecord.Columns.source == source.rawValue)
                .deleteAll(db)
            for var entity in entities {
                entity.id = nil
                entity.episodeUuid = episodeUuid
                entity.source = source.rawValue
                try entity.insert(db)
            }
        }
    }

    // MARK: - Reads

    /// Library-wide aggregate for one kind: entities with how many episodes
    /// and shows they appear in, most-cited first.
    public func entitiesAcrossLibrary(kind: MentionedEntityKind, limit: Int = 200) -> [MentionedEntityAggregate] {
        aggregates(sql: """
            SELECT canonicalKey, MIN(displayName) AS displayName, kind,
                   COUNT(DISTINCT episodeUuid) AS episodeCount,
                   COUNT(DISTINCT podcastUuid) AS podcastCount
            FROM MentionedEntity
            WHERE kind = ?
            GROUP BY canonicalKey
            ORDER BY episodeCount DESC, displayName ASC
            LIMIT ?
            """, arguments: [kind.rawValue, limit])
    }

    /// "Most cited on this show": one podcast's top entities of a kind.
    public func mostCited(kind: MentionedEntityKind, podcastUuid: String, limit: Int = 20) -> [MentionedEntityAggregate] {
        aggregates(sql: """
            SELECT canonicalKey, MIN(displayName) AS displayName, kind,
                   COUNT(DISTINCT episodeUuid) AS episodeCount,
                   COUNT(DISTINCT podcastUuid) AS podcastCount
            FROM MentionedEntity
            WHERE kind = ? AND podcastUuid = ?
            GROUP BY canonicalKey
            ORDER BY episodeCount DESC, displayName ASC
            LIMIT ?
            """, arguments: [kind.rawValue, podcastUuid, limit])
    }

    /// Every appearance of one entity, newest row first (the detail screen).
    public func appearances(kind: MentionedEntityKind, canonicalKey: String) -> [MentionedEntityRecord] {
        dbQueue.fetchAll(
            MentionedEntityRecord
                .filter(MentionedEntityRecord.Columns.kind == kind.rawValue)
                .filter(MentionedEntityRecord.Columns.canonicalKey == canonicalKey)
                .order(MentionedEntityRecord.Columns.createdAt.desc)
        )
    }

    /// Distinct podcasts (of the given set) where the entity appears — the
    /// "N shows you follow mentioned this" line. Pass subscribed uuids.
    public func podcastUuidsMentioning(kind: MentionedEntityKind, canonicalKey: String, within podcastUuids: [String]) -> [String] {
        guard !podcastUuids.isEmpty else { return [] }
        let rows = dbQueue.fetchAll(
            MentionedEntityRecord
                .filter(MentionedEntityRecord.Columns.kind == kind.rawValue)
                .filter(MentionedEntityRecord.Columns.canonicalKey == canonicalKey)
                .filter(podcastUuids.contains(MentionedEntityRecord.Columns.podcastUuid))
        )
        return Array(Set(rows.compactMap(\.podcastUuid)))
    }

    private func aggregates(sql: String, arguments: StatementArguments) -> [MentionedEntityAggregate] {
        dbQueue.read { db in
            // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - multi-DISTINCT GROUP BY aggregate the query interface can't express
            try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
                MentionedEntityAggregate(
                    canonicalKey: row["canonicalKey"],
                    displayName: row["displayName"],
                    kind: row["kind"],
                    episodeCount: row["episodeCount"],
                    podcastCount: row["podcastCount"]
                )
            }
        } ?? []
    }
}
