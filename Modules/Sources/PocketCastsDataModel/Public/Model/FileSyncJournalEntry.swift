import Foundation
import GRDB
import GRDBMacros

/// One pending local change awaiting flush to the file-sync folder.
///
/// This journal is file sync's own change source, deliberately independent
/// of the server-sync bookkeeping (`syncStatus` flags and the episode
/// `*Modified` stamps that `SyncTask.markAllSynced` zeroes after a push).
/// Rows are written transactionally alongside the local change and cleared
/// only after the file-sync flusher has durably written the corresponding
/// op to this device's log.
@GRDBRecord(table: "FileSyncJournal")
public struct FileSyncJournalEntry: Equatable, Sendable {
    public enum EntityType: Int32, Sendable {
        case podcast = 1
        case episode = 2
        case playlist = 3
        case folder = 4
        case bookmark = 5
        case userEpisode = 6
        case upNext = 7
        case setting = 8
        case stats = 9
    }

    public enum OpType: Int32, Sendable {
        /// Fields named in `fields` changed; the flusher reads the current
        /// row and emits a record op carrying just those fields.
        case upsert = 1
        /// Entity deleted; emits a tombstone (or deleted-flag record).
        case delete = 2
        case upNextPlayNow = 3
        case upNextPlayNext = 4
        case upNextPlayLast = 5
        case upNextRemove = 6
        /// `fields` holds the full ordered uuid list (JSON array).
        case upNextReplace = 7
        /// `fields` holds {"name": ..., "jsonValue": ...}.
        case settingChange = 8
    }

    public var id: Int64 = 0
    public var entityType: Int32 = 0
    public var entityUuid: String?
    public var opType: Int32 = 0
    /// JSON payload; meaning depends on `opType` (changed field names for
    /// upserts, uuid list for queue replaces, name/value for settings).
    public var fields: String?
    public var wallClockMs: Int64 = 0
    /// nil until written to a log file; then the per-device op seq it got.
    public var flushedSeq: Int64?

    public init(
        id: Int64 = 0,
        entityType: Int32 = 0,
        entityUuid: String? = nil,
        opType: Int32 = 0,
        fields: String? = nil,
        wallClockMs: Int64 = 0,
        flushedSeq: Int64? = nil
    ) {
        self.id = id
        self.entityType = entityType
        self.entityUuid = entityUuid
        self.opType = opType
        self.fields = fields
        self.wallClockMs = wallClockMs
        self.flushedSeq = flushedSeq
    }

    public var entity: EntityType? { EntityType(rawValue: entityType) }
    public var op: OpType? { OpType(rawValue: opType) }

    /// Decodes `fields` as the JSON array of changed field names used by
    /// upsert entries.
    public var changedFieldNames: [String] {
        guard let fields, let data = fields.data(using: .utf8),
              let names = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return names
    }
}
