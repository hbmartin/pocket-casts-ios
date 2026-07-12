import Foundation
@testable import PocketCastsServer
import XCTest

final class StatsManagerTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "StatsManagerTests.\(UUID().uuidString)"
        userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testPersistTimesWritesLatestStatsInOrder() {
        let manager = StatsManager(userDefaults: userDefaults)

        for _ in 0 ..< 100 {
            manager.addTimeSavedDynamicSpeed(1)
            manager.persistTimes()
        }
        manager.waitForPendingPersistence()

        let reloadedManager = StatsManager(userDefaults: userDefaults)
        XCTAssertEqual(reloadedManager.timeSavedDynamicSpeed(), 100)
    }

    func testUpdatedRemoteStatsArePersistedOutsideMutation() {
        let manager = StatsManager(userDefaults: userDefaults)

        manager.updateStatsIfNeeded(
            savedDynamicSpeed: 101,
            savedVariableSpeed: 102,
            totalListenedTo: 103,
            totalSkipped: 104,
            savedAutoSkipping: 105
        )
        manager.waitForPendingPersistence()

        let reloadedManager = StatsManager(userDefaults: userDefaults)
        XCTAssertEqual(reloadedManager.timeSavedDynamicSpeed(), 101)
        XCTAssertEqual(reloadedManager.timeSavedVariableSpeed(), 102)
        XCTAssertEqual(reloadedManager.totalListeningTime(), 103)
        XCTAssertEqual(reloadedManager.totalSkippedTime(), 104)
        XCTAssertEqual(reloadedManager.totalAutoSkippedTime(), 105)
    }

    func testMissingSyncStatusDefaultsToSynced() {
        let manager = StatsManager(userDefaults: userDefaults)

        XCTAssertEqual(manager.syncStatus(), .synced)
    }

    func testInitLoadsPersistedSyncStatus() {
        userDefaults.set(false, forKey: ServerConstants.UserDefaults.statsSyncStatus)
        let manager = StatsManager(userDefaults: userDefaults)

        manager.persistTimes()
        manager.waitForPendingPersistence()

        let reloadedManager = StatsManager(userDefaults: userDefaults)
        XCTAssertEqual(reloadedManager.syncStatus(), .notSynced)
    }

    func testSetSyncStatusUpdatesPendingPersistenceSnapshot() {
        let manager = StatsManager(userDefaults: userDefaults)
        manager.addTimeSavedDynamicSpeed(1)
        manager.persistTimes()

        manager.setSyncStatus(.synced)
        manager.persistTimes()
        manager.waitForPendingPersistence()

        XCTAssertEqual(manager.syncStatus(), .synced)
        let reloadedManager = StatsManager(userDefaults: userDefaults)
        XCTAssertEqual(reloadedManager.syncStatus(), .synced)
    }
}
