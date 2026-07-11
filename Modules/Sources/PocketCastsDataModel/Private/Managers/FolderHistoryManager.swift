import PocketCastsUtils
import Foundation
import GRDB
import GRDBMacros
import Synchronization

/// Row record for the `PodcastFoldersHistory` table.
/// `date` is a raw `timeIntervalSince1970` Double rather than a `Date`: the table does
/// exact-equality and GROUP BY on this column, and the legacy SQL path binds dates as
/// `timeIntervalSince1970` REALs — a `Date` property would encode as a datetime string
/// through the synthesized Codable conformance, splitting the storage format between paths.
@GRDBRecord(table: "PodcastFoldersHistory")
struct PodcastFolderHistoryRow: Equatable, Sendable {
    var podcastUuid = ""
    var folderUuid = ""
    var date: Double = 0
}

public class FolderHistoryManager {
    /// The number of days to keep the history
    private let periodOfSnapshot: TimeInterval = 14.days

    // MARK: - Queries

    /// Saves a list of podcast UUID and folders UUID so it can be
    /// restored later
    func snapshot(podcastsAndFolders: [String: String], dbQueue: GRDBQueue) {
        let date = Date().timeIntervalSince1970
        let cutoff = Date().addingTimeInterval(-periodOfSnapshot).timeIntervalSince1970
        dbQueue.write { db in
            for (podcastUuid, folderUuid) in podcastsAndFolders {
                try PodcastFolderHistoryRow(podcastUuid: podcastUuid, folderUuid: folderUuid, date: date).insert(db)
            }
            try PodcastFolderHistoryRow.filter(PodcastFolderHistoryRow.Columns.date <= cutoff).deleteAll(db)
        }
    }

    /// Return all the available Up Next entries
    func entries(dbQueue: GRDBQueue) -> [PodcastFoldersHistoryEntry] {
        let counts = dbQueue.read { db in
            try PodcastFolderHistoryRow
                .select(PodcastFolderHistoryRow.Columns.date, count(PodcastFolderHistoryRow.Columns.date).forKey("count"), as: HistoryDateCount.self)
                .group(PodcastFolderHistoryRow.Columns.date)
                .order(PodcastFolderHistoryRow.Columns.date.desc)
                .fetchAll(db)
        } ?? []

        return counts.map { PodcastFoldersHistoryEntry(date: Date(timeIntervalSince1970: $0.date), changesCount: $0.count) }
    }

    func podcastsAndFolders(entry: Date, dbQueue: GRDBQueue) -> [String: String] {
        let rows = dbQueue.fetchAll(PodcastFolderHistoryRow.filter(PodcastFolderHistoryRow.Columns.date == entry.timeIntervalSince1970))
        return Dictionary(rows.map { ($0.podcastUuid, $0.folderUuid) }, uniquingKeysWith: { _, last in last })
    }

    /// Decodes the aggregate `(date, COUNT(date))` rows produced by `entries(dbQueue:)`.
    private struct HistoryDateCount: Decodable, FetchableRecord {
        let date: Double
        let count: Int
    }

    public struct PodcastFoldersHistoryEntry: Hashable, Identifiable {
        public var id: Date {
            date
        }

        public let date: Date
        public let changesCount: Int
    }
}

public final class FolderHistoryHelper: Sendable {
    public static let shared = FolderHistoryHelper()

    private let podcastAndFolderUuids = Mutex<[String: String]>([:])

    public func add(podcastUuid: String, folderUuid: String) {
        podcastAndFolderUuids.withLock {
            $0[podcastUuid] = folderUuid
        }
    }

    public func snapshot() {
        let uuids: [String: String] = podcastAndFolderUuids.withLock { uuids in
            defer { uuids = [:] }
            return uuids
        }

        if !uuids.isEmpty {
            DataManager.sharedManager.snapshot(podcastsAndFolders: uuids)
        }
    }
}
