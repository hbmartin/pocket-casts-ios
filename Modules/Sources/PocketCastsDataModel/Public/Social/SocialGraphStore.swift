import Foundation
import GRDB
import GRDBMacros
import PocketCastsUtils

/// The kind of a local social relationship row. Stored in the `type` column.
public enum SocialRelationshipType: Int32, Sendable, CaseIterable {
    /// Mutual invisibility: neither party sees the other's profile or content,
    /// can follow, mention-resolve, or interact.
    case block = 0
    /// One-way hide: the muter stops seeing the muted party's content; the muted
    /// party is not notified and is otherwise unaffected.
    case mute = 1
}

/// Row record for `SocialRelationship` (migration 85): the device-local mirror
/// of one block or mute so the UI can filter instantly. The server is
/// authoritative — this table is a cache reconciled from it. One row per
/// `(targetUserId, type)`. Device-local only: nothing here syncs. Date columns
/// are raw `timeIntervalSince1970` Doubles, matching the other row records.
@GRDBRecord(table: "SocialRelationship")
public struct SocialRelationshipRecord: Equatable, Sendable {
    /// Immutable account uuid of the blocked/muted user (the canonical identity).
    public var targetUserId = ""

    /// Their handle when the relationship was recorded — a display convenience
    /// that may be stale (handles are immutable, but an operator reclaim can move one).
    public var targetHandle = ""

    /// Raw `SocialRelationshipType` value; prefer the typed `relationshipType` accessor.
    public var type: Int32 = 0

    public var addedDate: Double = 0

    public init() {}
}

public extension SocialRelationshipRecord {
    /// Typed view over the raw `type` column. Unknown raw values read as `.block`
    /// (fail safe toward the stronger restriction).
    var relationshipType: SocialRelationshipType {
        get { SocialRelationshipType(rawValue: type) ?? .block }
        set { type = newValue.rawValue }
    }
}

/// Data access for the local social graph (blocks + mutes): idempotent
/// add/remove on block/mute/unblock/unmute, `replace` to reconcile the local
/// mirror after fetching the authoritative list from the server, and the
/// membership queries the UI uses to hide people. See docs/SocialModeration.md
/// and ADR-0007.
public struct SocialGraphStore: Sendable {
    static let tableName = "SocialRelationship"

    private let dbQueue: GRDBQueue

    init(dbQueue: GRDBQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Mutations

    /// Records a block or mute. Idempotent: re-recording upserts on the
    /// `(targetUserId, type)` primary key, refreshing the handle and date.
    @discardableResult
    public func add(targetUserId: String, handle: String = "", type: SocialRelationshipType) -> Bool {
        var record = SocialRelationshipRecord()
        record.targetUserId = targetUserId
        record.targetHandle = handle
        record.relationshipType = type
        record.addedDate = Date().timeIntervalSince1970
        let success = dbQueue.write { db in
            try record.save(db)
        }
        if !success { FileLog.shared.addMessage("SocialGraphStore.add failed") }
        return success
    }

    /// Removes a block or mute for the user (unblock / unmute). Idempotent.
    @discardableResult
    public func remove(targetUserId: String, type: SocialRelationshipType) -> Bool {
        let success = dbQueue.write { db in
            _ = try SocialRelationshipRecord
                .filter(SocialRelationshipRecord.Columns.targetUserId == targetUserId)
                .filter(SocialRelationshipRecord.Columns.type == type.rawValue)
                .deleteAll(db)
        }
        if !success { FileLog.shared.addMessage("SocialGraphStore.remove failed") }
        return success
    }

    /// Replaces every row of one type with the given set — reconciles the local
    /// mirror after fetching the authoritative list from the server.
    @discardableResult
    public func replace(_ records: [SocialRelationshipRecord], type: SocialRelationshipType) -> Bool {
        let stamped = records.map { record -> SocialRelationshipRecord in
            var record = record
            record.relationshipType = type
            if record.addedDate == 0 { record.addedDate = Date().timeIntervalSince1970 }
            return record
        }
        let success = dbQueue.write { db in
            _ = try SocialRelationshipRecord
                .filter(SocialRelationshipRecord.Columns.type == type.rawValue)
                .deleteAll(db)
            for record in stamped { try record.save(db) }
        }
        if !success { FileLog.shared.addMessage("SocialGraphStore.replace failed") }
        return success
    }

    /// Clears the entire local graph (e.g. on logout / account erase).
    @discardableResult
    public func removeAll() -> Bool {
        let success = dbQueue.write { db in
            _ = try SocialRelationshipRecord.deleteAll(db)
        }
        if !success { FileLog.shared.addMessage("SocialGraphStore.removeAll failed") }
        return success
    }

    // MARK: - Queries

    public func isBlocked(_ targetUserId: String) -> Bool {
        contains(targetUserId: targetUserId, type: .block)
    }

    public func isMuted(_ targetUserId: String) -> Bool {
        contains(targetUserId: targetUserId, type: .mute)
    }

    /// Every uuid the viewer has blocked or muted — the hide-set the UI applies
    /// when rendering people or content.
    public func hiddenUserIds() -> Set<String> {
        let records = dbQueue.fetchAll(SocialRelationshipRecord.order(SocialRelationshipRecord.Columns.addedDate.desc))
        return Set(records.map(\.targetUserId))
    }

    /// All blocks or all mutes, newest first.
    public func all(type: SocialRelationshipType) -> [SocialRelationshipRecord] {
        dbQueue.fetchAll(SocialRelationshipRecord
            .filter(SocialRelationshipRecord.Columns.type == type.rawValue)
            .order(SocialRelationshipRecord.Columns.addedDate.desc))
    }

    // MARK: - Private

    private func contains(targetUserId: String, type: SocialRelationshipType) -> Bool {
        let request = SocialRelationshipRecord
            .filter(SocialRelationshipRecord.Columns.targetUserId == targetUserId)
            .filter(SocialRelationshipRecord.Columns.type == type.rawValue)
        return dbQueue.fetchOne(request) != nil
    }
}
