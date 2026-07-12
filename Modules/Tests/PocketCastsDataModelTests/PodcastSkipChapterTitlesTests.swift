import XCTest
@testable import PocketCastsDataModel
@testable import PocketCastsUtils

/// Covers the additive `skipChapterTitles` field on the PodcastSettings JSON payload:
/// decode compatibility with payloads written before the field existed, and the
/// flag-independent persistence path.
final class PodcastSkipChapterTitlesTests: DataManagerTestCase {
    // MARK: - Codable compatibility

    func testSettingsPayloadWithoutTheFieldStillDecodes() throws {
        // A payload written before skipChapterTitles existed
        let oldPayload = try XCTUnwrap(PodcastSettings.defaults.jsonData.flatMap { data -> Data? in
            var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            object?.removeValue(forKey: "skipChapterTitles")
            return object.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        })

        let decoded = try JSONDecoder().decode(PodcastSettings.self, from: oldPayload)

        XCTAssertNil(decoded.skipChapterTitles, "A missing key should decode as nil, not throw")
    }

    func testSettingsPayloadRoundTripsTheField() throws {
        var settings = PodcastSettings.defaults
        settings.skipChapterTitles = ["sponsor", "ad break"]

        let data = try XCTUnwrap(settings.jsonData)
        let decoded = try JSONDecoder().decode(PodcastSettings.self, from: data)

        XCTAssertEqual(decoded.skipChapterTitles, ["sponsor", "ad break"])
    }

    // MARK: - Persistence

    func testSaveSkipChapterTitlesPersistsIndependentlyOfTheSettingsFlag() throws {
        // newSettingsStorage is NOT overridden here: the write must work with the flag off
        try runWithBothImplementations { dataManager, impl in
            let podcast = self.createTestPodcast(uuid: "skip-chapters-podcast", dataManager: dataManager)

            dataManager.saveSkipChapterTitles(["sponsor", "intro"], podcastUuid: podcast.uuid)

            let found = try XCTUnwrap(dataManager.findPodcast(uuid: podcast.uuid), "\(impl): Podcast should still be readable")
            XCTAssertEqual(found.settings.skipChapterTitles, ["sponsor", "intro"], "\(impl): Titles should persist in the settings payload")
            XCTAssertEqual(found.syncStatus, SyncStatus.notSynced.rawValue, "\(impl): Podcast should be marked unsynced")
        }
    }

    func testSaveSkipChapterTitlesPreservesOtherSettingsAndSupportsRemoval() throws {
        try runWithBothImplementations { dataManager, impl in
            let podcast = self.createTestPodcast(uuid: "skip-chapters-podcast-2", dataManager: dataManager)
            var settings = PodcastSettings.defaults
            settings.playbackSpeed = 1.7
            let settingsJson = try XCTUnwrap(settings.jsonData.flatMap { String(data: $0, encoding: .utf8) })
            try dataManager.setPodcastSettingsForTest(podcastUuid: podcast.uuid, settings: settingsJson)

            dataManager.saveSkipChapterTitles(["sponsor"], podcastUuid: podcast.uuid)
            dataManager.saveSkipChapterTitles([], podcastUuid: podcast.uuid)

            let found = try XCTUnwrap(dataManager.findPodcast(uuid: podcast.uuid), "\(impl): Podcast should still be readable")
            XCTAssertEqual(found.settings.skipChapterTitles, [], "\(impl): Clearing the list should persist an empty list")
            XCTAssertEqual(found.settings.playbackSpeed, 1.7, "\(impl): json_set must preserve unrelated settings")
        }
    }
}
