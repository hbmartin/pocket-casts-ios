import XCTest
import GRDB
@testable import PocketCastsDataModel
@testable import PocketCastsUtils

/// Parity tests for AutoAddCandidatesDataManager running every case with both SQL and GRDB
/// implementations, across both `newSettingsStorage` states where the read path differs.
/// (AutoAddCandidatesDataManagerTests covers the settings-flag behavior on the default DB path.)
final class AutoAddCandidatesParityTests: DataManagerTestCase {

    private let settingsFlagMock = FeatureFlagMock()

    override func tearDown() async throws {
        settingsFlagMock.reset()
        try await super.tearDown()
    }

    // MARK: - add / candidates

    func testCandidateMapsSettingWithNewSettingsStorage() throws {
        settingsFlagMock.set(.newSettingsStorage, value: true)

        try runWithBothImplementations { dataManager, impl in
            let podcast = self.createTestPodcast(withUpNextSetting: .addFirst, dataManager: dataManager)
            dataManager.autoAddCandidates.add(podcastUUID: podcast.uuid, episodeUUID: "episode-1")

            let candidates = dataManager.autoAddCandidates.candidates()

            XCTAssertEqual(candidates.count, 1, "\(impl): Should list the added candidate")
            XCTAssertEqual(candidates.first?.episodeUuid, "episode-1", "\(impl): Candidate should carry the episode uuid")
            XCTAssertEqual(candidates.first?.autoAddToUpNextSetting, .addFirst, "\(impl): Setting should map from the settings payload")
        }
    }

    func testCandidateMapsSettingWithLegacySettingsStorage() throws {
        settingsFlagMock.set(.newSettingsStorage, value: false)

        try runWithBothImplementations { dataManager, impl in
            let podcast = self.createTestPodcast(withUpNextSetting: .addFirst, dataManager: dataManager)
            dataManager.autoAddCandidates.add(podcastUUID: podcast.uuid, episodeUUID: "episode-1")

            let candidates = dataManager.autoAddCandidates.candidates()

            XCTAssertEqual(candidates.count, 1, "\(impl): Should list the added candidate")
            XCTAssertEqual(candidates.first?.autoAddToUpNextSetting, .addFirst, "\(impl): Setting should map from the autoAddToUpNext column")
        }
    }

    func testCandidateWithEmptySettingsPayloadDefaultsToAddLast() throws {
        settingsFlagMock.set(.newSettingsStorage, value: true)

        try runWithBothImplementations { dataManager, impl in
            let podcast = self.createTestPodcast(withUpNextSetting: .addFirst, dataManager: dataManager)
            dataManager.autoAddCandidates.add(podcastUUID: podcast.uuid, episodeUUID: "episode-1")

            // A settings payload without the key: json_extract yields NULL, which both paths
            // must read as 0 → UpNextPosition.bottom → addLast
            dataManager.dbQueue.write { db in
                do {
                    try db.executeUpdate("UPDATE \(DataManager.podcastTableName) SET settings = '{}' WHERE uuid = ?", values: [podcast.uuid])
                } catch {
                    XCTFail("Failed to clear settings payload: \(error)")
                }
            }

            let candidates = dataManager.autoAddCandidates.candidates()

            XCTAssertEqual(candidates.first?.autoAddToUpNextSetting, .addLast, "\(impl): Missing settings key should read as bottom/addLast")
        }
    }

    func testCandidatesAreOrderedOldestFirst() throws {
        settingsFlagMock.set(.newSettingsStorage, value: false)

        try runWithBothImplementations { dataManager, impl in
            let podcast = self.createTestPodcast(withUpNextSetting: .addLast, dataManager: dataManager)
            dataManager.autoAddCandidates.add(podcastUUID: podcast.uuid, episodeUUID: "episode-1")
            dataManager.autoAddCandidates.add(podcastUUID: podcast.uuid, episodeUUID: "episode-2")
            dataManager.autoAddCandidates.add(podcastUUID: podcast.uuid, episodeUUID: "episode-3")

            let candidates = dataManager.autoAddCandidates.candidates()

            XCTAssertEqual(candidates.map(\.episodeUuid), ["episode-1", "episode-2", "episode-3"], "\(impl): Candidates should process oldest first")
        }
    }

    func testCandidateWithoutMatchingPodcastIsDropped() throws {
        settingsFlagMock.set(.newSettingsStorage, value: false)

        try runWithBothImplementations { dataManager, impl in
            let podcast = self.createTestPodcast(withUpNextSetting: .addLast, dataManager: dataManager)
            dataManager.autoAddCandidates.add(podcastUUID: podcast.uuid, episodeUUID: "episode-1")
            dataManager.autoAddCandidates.add(podcastUUID: "missing-podcast", episodeUUID: "episode-orphan")

            let candidates = dataManager.autoAddCandidates.candidates()

            XCTAssertEqual(candidates.map(\.episodeUuid), ["episode-1"], "\(impl): Candidates without a podcast row should be dropped")
        }
    }

    // MARK: - remove / clearAll

    func testRemoveDeletesOnlyThatCandidate() throws {
        settingsFlagMock.set(.newSettingsStorage, value: false)

        try runWithBothImplementations { dataManager, impl in
            let podcast = self.createTestPodcast(withUpNextSetting: .addLast, dataManager: dataManager)
            dataManager.autoAddCandidates.add(podcastUUID: podcast.uuid, episodeUUID: "episode-1")
            dataManager.autoAddCandidates.add(podcastUUID: podcast.uuid, episodeUUID: "episode-2")

            guard let toRemove = dataManager.autoAddCandidates.candidates().first(where: { $0.episodeUuid == "episode-1" }) else {
                XCTFail("\(impl): Should find the candidate to remove")
                return
            }
            dataManager.autoAddCandidates.remove(toRemove)

            let candidates = dataManager.autoAddCandidates.candidates()

            XCTAssertEqual(candidates.map(\.episodeUuid), ["episode-2"], "\(impl): Only the removed candidate should be gone")
        }
    }

    func testClearAllEmptiesTheQueue() throws {
        settingsFlagMock.set(.newSettingsStorage, value: false)

        try runWithBothImplementations { dataManager, impl in
            let podcast = self.createTestPodcast(withUpNextSetting: .addLast, dataManager: dataManager)
            dataManager.autoAddCandidates.add(podcastUUID: podcast.uuid, episodeUUID: "episode-1")
            dataManager.autoAddCandidates.add(podcastUUID: podcast.uuid, episodeUUID: "episode-2")

            dataManager.autoAddCandidates.clearAll()

            XCTAssertTrue(dataManager.autoAddCandidates.candidates().isEmpty, "\(impl): clearAll should remove every candidate")
        }
    }

    // MARK: - Helpers

    private func createTestPodcast(withUpNextSetting setting: AutoAddToUpNextSetting, dataManager: DataManager) -> Podcast {
        var podcast = Podcast()
        podcast.uuid = UUID().uuidString
        podcast.title = "Test Podcast"
        podcast.addedDate = Date()
        podcast.setAutoAddToUpNext(setting: setting)
        return dataManager.save(podcast: podcast)
    }
}
