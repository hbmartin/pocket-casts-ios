import XCTest
import GRDB
@testable import PocketCastsDataModel

final class NetworkDataUsageManagerTests: XCTestCase {
    private var dataManager: DataManager!

    override func setUp() {
        super.setUp()
        dataManager = DataManager.newTestDataManager()
    }

    override func tearDown() {
        dataManager = nil
        super.tearDown()
    }

    // MARK: - Adding Records

    func testAddRecordSucceeds() {
        let result = dataManager.networkDataUsageManager.add(
            episodeUuid: "ep-1",
            podcastUuid: "pod-1",
            bytesDownloaded: 1024,
            operationType: .download,
            connectionType: .cellular
        )
        XCTAssertTrue(result)
    }

    func testAddPersistsAllFields() throws {
        let timestamp = Date()
        let result = dataManager.networkDataUsageManager.add(
            episodeUuid: "ep-1",
            podcastUuid: "pod-1",
            bytesDownloaded: 1024,
            bytesStreamed: 2048,
            bytesUploaded: 512,
            operationType: .stream,
            connectionType: .wifi,
            sessionType: .background,
            timestamp: timestamp
        )
        XCTAssertTrue(result)

        let record = try XCTUnwrap(fetchRecords().first)
        XCTAssertNotNil(record.id, "SQLite should assign the AUTOINCREMENT id")
        XCTAssertEqual(record.timestamp, timestamp.timeIntervalSince1970)
        XCTAssertEqual(record.episodeUuid, "ep-1")
        XCTAssertEqual(record.podcastUuid, "pod-1")
        XCTAssertEqual(record.bytesDownloaded, 1024)
        XCTAssertEqual(record.bytesStreamed, 2048)
        XCTAssertEqual(record.bytesUploaded, 512)
        XCTAssertEqual(record.operationType, NetworkDataUsageManager.OperationType.stream.rawValue)
        XCTAssertEqual(record.connectionType, Int32(NetworkDataUsageManager.ConnectionType.wifi.rawValue))
        XCTAssertEqual(record.sessionType, NetworkDataUsageManager.SessionType.background.rawValue)
    }

    func testAddWithDefaultsStoresNulls() throws {
        XCTAssertTrue(dataManager.networkDataUsageManager.add(operationType: .api, connectionType: .unknown))

        let record = try XCTUnwrap(fetchRecords().first)
        XCTAssertNil(record.episodeUuid)
        XCTAssertNil(record.podcastUuid)
        XCTAssertNil(record.sessionType)
        XCTAssertEqual(record.bytesDownloaded, 0)
    }

    func testAddAssignsDistinctIds() {
        XCTAssertTrue(dataManager.networkDataUsageManager.add(operationType: .download, connectionType: .wifi))
        XCTAssertTrue(dataManager.networkDataUsageManager.add(operationType: .download, connectionType: .wifi))

        let ids = fetchRecords().compactMap(\.id)
        XCTAssertEqual(ids.count, 2, "Both inserts should persist with assigned ids")
        XCTAssertEqual(Set(ids).count, 2, "AUTOINCREMENT ids should be distinct")
    }

    // MARK: - Delete Records

    func testDeleteRecordsOlderThanDate() async {
        let now = Date()

        // Old record
        dataManager.networkDataUsageManager.add(
            bytesDownloaded: 100,
            operationType: .download,
            connectionType: .cellular,
            timestamp: now.addingTimeInterval(-7200)
        )

        // Recent record
        dataManager.networkDataUsageManager.add(
            bytesDownloaded: 200,
            operationType: .download,
            connectionType: .cellular,
            timestamp: now
        )

        let cutoff = now.addingTimeInterval(-3600)
        let result = await dataManager.networkDataUsageManager.deleteRecords(olderThan: cutoff)
        XCTAssertTrue(result)

        let totalCount = recordCount()
        let recentCount = recordCount(since: cutoff)
        XCTAssertEqual(totalCount, 1)
        XCTAssertEqual(recentCount, 1)
    }

    // MARK: - Helpers

    private func fetchRecords() -> [NetworkDataUsageRecord] {
        guard let grdbQueue = dataManager.dbQueue as? GRDBQueue else { return [] }
        return grdbQueue.fetchAll(NetworkDataUsageRecord.order(NetworkDataUsageRecord.Columns.id.asc))
    }

    private func recordCount(since date: Date? = nil) -> Int {
        if let date {
            return dataManager.count(
                query: "SELECT COUNT(*) FROM \(NetworkDataUsageManager.tableName) WHERE timestamp >= ?",
                values: [date.timeIntervalSince1970]
            )
        }
        return dataManager.count(
            query: "SELECT COUNT(*) FROM \(NetworkDataUsageManager.tableName)",
            values: nil
        )
    }
}
