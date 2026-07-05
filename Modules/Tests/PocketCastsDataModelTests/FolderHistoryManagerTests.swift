import XCTest
import GRDB
@testable import PocketCastsDataModel
@testable import PocketCastsUtils

/// Tests for FolderHistoryManager using the public DataManager API.
/// These tests run with both SQL and GRDB implementations.
final class FolderHistoryManagerTests: DataManagerTestCase {

    // MARK: - snapshot Tests

    func testSnapshotCreatesEntryWithChangeCount() throws {
        try runWithBothImplementations { dataManager, impl in
            dataManager.snapshot(podcastsAndFolders: [
                "podcast-1": "folder-1",
                "podcast-2": "folder-1",
                "podcast-3": "folder-2"
            ])

            let entries = dataManager.foldersHistoryEntries()

            XCTAssertEqual(entries.count, 1, "\(impl): One snapshot should produce one entry")
            XCTAssertEqual(entries.first?.changesCount, 3, "\(impl): Entry should count all snapshotted podcasts")
        }
    }

    func testSnapshotWithEmptyMapCreatesNoEntries() throws {
        try runWithBothImplementations { dataManager, impl in
            dataManager.snapshot(podcastsAndFolders: [:])

            let entries = dataManager.foldersHistoryEntries()

            XCTAssertTrue(entries.isEmpty, "\(impl): An empty snapshot should not create entries")
        }
    }

    func testSnapshotPrunesEntriesOlderThanRetentionPeriod() throws {
        try runWithBothImplementations { dataManager, impl in
            let oldDate = Date().addingTimeInterval(-15.days)
            self.insertHistoryRow(podcastUuid: "podcast-old", folderUuid: "folder-old", date: oldDate, dataManager: dataManager)
            let recentDate = Date().addingTimeInterval(-1.days)
            self.insertHistoryRow(podcastUuid: "podcast-recent", folderUuid: "folder-recent", date: recentDate, dataManager: dataManager)

            dataManager.snapshot(podcastsAndFolders: ["podcast-1": "folder-1"])

            let entries = dataManager.foldersHistoryEntries()

            XCTAssertEqual(entries.count, 2, "\(impl): The entry older than 14 days should be pruned")
            XCTAssertFalse(
                entries.contains { abs($0.date.timeIntervalSince(oldDate)) < 1 },
                "\(impl): The pruned entry should not be listed"
            )
        }
    }

    // MARK: - entries Tests

    func testEntriesReturnsEmptyWhenNoHistory() throws {
        try runWithBothImplementations { dataManager, impl in
            let entries = dataManager.foldersHistoryEntries()

            XCTAssertTrue(entries.isEmpty, "\(impl): Should return no entries for an empty table")
        }
    }

    func testEntriesAreOrderedNewestFirst() throws {
        try runWithBothImplementations { dataManager, impl in
            let older = Date().addingTimeInterval(-2.days)
            let newer = Date().addingTimeInterval(-1.days)
            self.insertHistoryRow(podcastUuid: "podcast-1", folderUuid: "folder-1", date: older, dataManager: dataManager)
            self.insertHistoryRow(podcastUuid: "podcast-2", folderUuid: "folder-2", date: newer, dataManager: dataManager)

            let entries = dataManager.foldersHistoryEntries()

            XCTAssertEqual(entries.count, 2, "\(impl): Should list one entry per snapshot date")
            XCTAssertEqual(entries.map(\.date), entries.map(\.date).sorted(by: >), "\(impl): Entries should be ordered newest first")
        }
    }

    func testEntriesGroupsRowsBySnapshotDate() throws {
        try runWithBothImplementations { dataManager, impl in
            let firstSnapshot = Date().addingTimeInterval(-2.days)
            let secondSnapshot = Date().addingTimeInterval(-1.days)
            self.insertHistoryRow(podcastUuid: "podcast-1", folderUuid: "folder-1", date: firstSnapshot, dataManager: dataManager)
            self.insertHistoryRow(podcastUuid: "podcast-2", folderUuid: "folder-1", date: firstSnapshot, dataManager: dataManager)
            self.insertHistoryRow(podcastUuid: "podcast-3", folderUuid: "folder-2", date: secondSnapshot, dataManager: dataManager)

            let entries = dataManager.foldersHistoryEntries()

            XCTAssertEqual(entries.count, 2, "\(impl): Rows sharing a date should group into one entry")
            XCTAssertEqual(entries.first?.changesCount, 1, "\(impl): The newest entry has one change")
            XCTAssertEqual(entries.last?.changesCount, 2, "\(impl): The oldest entry has two changes")
        }
    }

    // MARK: - folderHistory (podcastsAndFolders) Tests

    func testFolderHistoryReturnsMappingForEntryDate() throws {
        try runWithBothImplementations { dataManager, impl in
            dataManager.snapshot(podcastsAndFolders: [
                "podcast-1": "folder-1",
                "podcast-2": "folder-2"
            ])

            guard let entry = dataManager.foldersHistoryEntries().first else {
                XCTFail("\(impl): Snapshot should produce an entry")
                return
            }

            let history = dataManager.folderHistory(entry: entry.date)

            XCTAssertEqual(history, ["podcast-1": "folder-1", "podcast-2": "folder-2"], "\(impl): Should restore the snapshotted mapping")
        }
    }

    func testFolderHistoryReturnsEmptyForUnknownDate() throws {
        try runWithBothImplementations { dataManager, impl in
            dataManager.snapshot(podcastsAndFolders: ["podcast-1": "folder-1"])

            let history = dataManager.folderHistory(entry: Date(timeIntervalSince1970: 1000))

            XCTAssertTrue(history.isEmpty, "\(impl): Should return an empty mapping for a date with no snapshot")
        }
    }

    func testFolderHistoryOnlyReturnsRowsForRequestedSnapshot() throws {
        try runWithBothImplementations { dataManager, impl in
            let firstSnapshot = Date().addingTimeInterval(-2.days)
            let secondSnapshot = Date().addingTimeInterval(-1.days)
            self.insertHistoryRow(podcastUuid: "podcast-1", folderUuid: "folder-1", date: firstSnapshot, dataManager: dataManager)
            self.insertHistoryRow(podcastUuid: "podcast-2", folderUuid: "folder-2", date: secondSnapshot, dataManager: dataManager)

            let entries = dataManager.foldersHistoryEntries()
            XCTAssertEqual(entries.count, 2, "\(impl): Should list both snapshots")

            guard let newest = entries.first else { return }
            let history = dataManager.folderHistory(entry: newest.date)

            XCTAssertEqual(history, ["podcast-2": "folder-2"], "\(impl): Should only return the requested snapshot's rows")
        }
    }

    // MARK: - Column Consistency

    /// The legacy path inserts with a positional `INSERT INTO PodcastFoldersHistory VALUES (?, ?, ?)`,
    /// so the table's column order must match what both paths write.
    func testDatabaseTableColumnsMatchRecord() throws {
        let dataManager = DataManager.newTestDataManager()

        let grdbQueue = dataManager.dbQueue

        let tableColumns = try grdbQueue.dbPool.read { db -> [String] in
            try db.columns(in: PodcastFolderHistoryRow.databaseTableName).map { $0.name }
        }

        XCTAssertEqual(tableColumns, ["podcastUuid", "folderUuid", "date"], "Table columns must stay in the order the legacy positional INSERT expects")
    }

    // MARK: - Helpers

    /// Inserts a history row with a controlled date. Uses the legacy shim directly (independent of
    /// the feature flag) — it binds `Date` as a `timeIntervalSince1970` REAL, the storage format
    /// shared by both implementations.
    private func insertHistoryRow(podcastUuid: String, folderUuid: String, date: Date, dataManager: DataManager) {
        dataManager.dbQueue.write { db in
            do {
                try db.executeUpdate("INSERT INTO PodcastFoldersHistory VALUES (?, ?, ?)", values: [podcastUuid, folderUuid, date])
            } catch {
                XCTFail("Failed to insert history row: \(error)")
            }
        }
    }
}
