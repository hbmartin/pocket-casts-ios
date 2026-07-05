import PocketCastsUtils
import Foundation
import GRDB
import GRDBMacros

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
    func snapshot(podcastsAndFolders: [String: String], dbQueue: PCDBQueue) {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            let date = Date().timeIntervalSince1970
            let cutoff = Date().addingTimeInterval(-periodOfSnapshot).timeIntervalSince1970
            grdbQueue.write { db in
                for (podcastUuid, folderUuid) in podcastsAndFolders {
                    try PodcastFolderHistoryRow(podcastUuid: podcastUuid, folderUuid: folderUuid, date: date).insert(db)
                }
                try PodcastFolderHistoryRow.filter(PodcastFolderHistoryRow.Columns.date <= cutoff).deleteAll(db)
            }
            return
        }

        dbQueue.write { db in
            do {
                db.beginTransaction()

                let date = Date()
                try podcastsAndFolders.forEach {
                    try db.executeUpdate("INSERT INTO PodcastFoldersHistory VALUES (?, ?, ?)", values: [$0.key, $0.value, date])
                }
                try db.executeUpdate("DELETE FROM PodcastFoldersHistory WHERE date <= ?", values: [Date().addingTimeInterval(-periodOfSnapshot)])

                db.commit()
            } catch {
                FileLog.shared.addMessage("FolderHistoryManager.snapshot error: \(error)")
            }
        }
    }

    /// Return all the available Up Next entries
    func entries(dbQueue: PCDBQueue) -> [PodcastFoldersHistoryEntry] {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            let counts = grdbQueue.read { db in
                try PodcastFolderHistoryRow
                    .select(PodcastFolderHistoryRow.Columns.date, count(PodcastFolderHistoryRow.Columns.date).forKey("count"), as: HistoryDateCount.self)
                    .group(PodcastFolderHistoryRow.Columns.date)
                    .order(PodcastFolderHistoryRow.Columns.date.desc)
                    .fetchAll(db)
            } ?? []

            return counts.map { PodcastFoldersHistoryEntry(date: Date(timeIntervalSince1970: $0.date), changesCount: $0.count) }
        }

        var entries: [PodcastFoldersHistoryEntry] = []
        dbQueue.read { db in
            do {
                let resultSet = try db.executeQuery("SELECT COUNT(*) as count, date FROM PodcastFoldersHistory GROUP BY (date) ORDER BY date DESC", values: nil)
                defer { resultSet.close() }

                while resultSet.next() {
                    if let date = resultSet.date(forColumn: "date") {
                        entries.append(PodcastFoldersHistoryEntry(date: date, changesCount: Int(resultSet.int(forColumn: "count"))))
                    }
                }
            } catch {
                FileLog.shared.addMessage("FolderHistoryManager.entries error: \(error)")
            }
        }

        return entries
    }

    func podcastsAndFolders(entry: Date, dbQueue: PCDBQueue) -> [String: String] {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            let rows = grdbQueue.fetchAll(PodcastFolderHistoryRow.filter(PodcastFolderHistoryRow.Columns.date == entry.timeIntervalSince1970))
            return Dictionary(rows.map { ($0.podcastUuid, $0.folderUuid) }, uniquingKeysWith: { _, last in last })
        }

        var podcastsAndFolders: [String: String] = [:]
        dbQueue.read { db in
            do {
                let resultSet = try db.executeQuery("SELECT podcastUuid, folderUuid FROM PodcastFoldersHistory WHERE date = ?", values: [entry])
                defer { resultSet.close() }

                while resultSet.next() {
                    if let podcastUuid = resultSet.string(forColumn: "podcastUuid"),
                       let folderUuid = resultSet.string(forColumn: "folderUuid") {
                        podcastsAndFolders[podcastUuid] = folderUuid
                    }
                }
            } catch {
                FileLog.shared.addMessage("FolderHistoryManager.podcastsAndFolders error: \(error)")
            }
        }

        return podcastsAndFolders
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

// @unchecked Sendable: `podcastAndFolderUuids` is guarded by `lock`.
public final class FolderHistoryHelper: @unchecked Sendable {
    public static let shared = FolderHistoryHelper()

    private let lock = NSLock()
    private var podcastAndFolderUuids: [String: String] = [:]

    public func add(podcastUuid: String, folderUuid: String) {
        lock.withLock {
            podcastAndFolderUuids[podcastUuid] = folderUuid
        }
    }

    public func snapshot() {
        let uuids: [String: String] = lock.withLock {
            defer { podcastAndFolderUuids = [:] }
            return podcastAndFolderUuids
        }

        if !uuids.isEmpty {
            DataManager.sharedManager.snapshot(podcastsAndFolders: uuids)
        }
    }
}
