import XCTest
@testable import PocketCastsDataModel
@testable import PocketCastsUtils

/// Covers the additive `autoTranscribe` field on the PodcastSettings JSON payload:
/// decode compatibility with payloads written before the field existed (via the
/// module-scoped `ModifiedDate<Bool>` missing-key rescue) and the flag-independent
/// persistence path.
final class PodcastAutoTranscribeSettingTests: DataManagerTestCase {
    // MARK: - Codable compatibility

    func testSettingsPayloadWithoutTheFieldDecodesAsFalse() throws {
        // A payload written before autoTranscribe existed
        let oldPayload = try XCTUnwrap(PodcastSettings.defaults.jsonData.flatMap { data -> Data? in
            var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            object?.removeValue(forKey: "autoTranscribe")
            return object.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        })

        let decoded = try JSONDecoder().decode(PodcastSettings.self, from: oldPayload)

        XCTAssertFalse(decoded.autoTranscribe, "A missing key should decode as false, not throw")
        XCTAssertEqual(decoded.playbackSpeed, 1, "The rest of the payload must survive the missing key")
    }

    func testSettingsPayloadRoundTripsTheField() throws {
        var settings = PodcastSettings.defaults
        settings.autoTranscribe = true

        let data = try XCTUnwrap(settings.jsonData)
        let decoded = try JSONDecoder().decode(PodcastSettings.self, from: data)

        XCTAssertTrue(decoded.autoTranscribe)
    }

    // MARK: - Persistence

    func testSaveAutoTranscribePersistsIndependentlyOfTheSettingsFlag() throws {
        // newSettingsStorage is NOT overridden here: the write must work with the flag off
        try runWithBothImplementations { dataManager, impl in
            let podcast = self.createTestPodcast(uuid: "auto-transcribe-podcast", dataManager: dataManager)

            dataManager.saveAutoTranscribe(true, podcastUuid: podcast.uuid)

            let found = try XCTUnwrap(dataManager.findPodcast(uuid: podcast.uuid), "\(impl): Podcast should still be readable")
            XCTAssertTrue(found.settings.autoTranscribe, "\(impl): The opt-in should persist in the settings payload")
            XCTAssertEqual(found.syncStatus, SyncStatus.notSynced.rawValue, "\(impl): Podcast should be marked unsynced")
        }
    }

    func testSaveAutoTranscribePreservesOtherSettingsAndSupportsDisabling() throws {
        try runWithBothImplementations { dataManager, impl in
            let podcast = self.createTestPodcast(uuid: "auto-transcribe-podcast-2", dataManager: dataManager)
            var settings = PodcastSettings.defaults
            settings.playbackSpeed = 1.7
            let settingsJson = try XCTUnwrap(settings.jsonData.flatMap { String(data: $0, encoding: .utf8) })
            try dataManager.setPodcastSettingsForTest(podcastUuid: podcast.uuid, settings: settingsJson)

            dataManager.saveAutoTranscribe(true, podcastUuid: podcast.uuid)
            dataManager.saveAutoTranscribe(false, podcastUuid: podcast.uuid)

            let found = try XCTUnwrap(dataManager.findPodcast(uuid: podcast.uuid), "\(impl): Podcast should still be readable")
            XCTAssertFalse(found.settings.autoTranscribe, "\(impl): Disabling should persist")
            XCTAssertEqual(found.settings.playbackSpeed, 1.7, "\(impl): json_set must preserve unrelated settings")
        }
    }
}
