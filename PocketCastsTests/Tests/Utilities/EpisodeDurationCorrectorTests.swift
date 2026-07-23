import PocketCastsDataModel
import XCTest

@testable import podcasts

final class EpisodeDurationCorrectorTests: XCTestCase {
    func testNearIdenticalValuesAreNotCorrected() {
        XCTAssertNil(EpisodeDurationCorrector.correction(current: 4319, calculated: 4319.4))
    }

    func testSmallCorrectionUpdatesWithoutSync() {
        let result = EpisodeDurationCorrector.correction(current: 4319, calculated: 4330)
        XCTAssertEqual(result?.duration, 4330)
        XCTAssertEqual(result?.syncFlag, false)
    }

    func testLargeCorrectionUpdatesAndSyncs() {
        // The reported case: feed said "1h 6m" for a 1h 12m episode.
        let result = EpisodeDurationCorrector.correction(current: 3960, calculated: 4319)
        XCTAssertEqual(result?.duration, 4319)
        XCTAssertEqual(result?.syncFlag, true)
    }

    func testImplausibleMeasurementsAreRejected() {
        XCTAssertNil(EpisodeDurationCorrector.correction(current: 60, calculated: 5), "shorter than 10s is not a podcast")
        XCTAssertNil(EpisodeDurationCorrector.correction(current: 60, calculated: 40000), "longer than 10h is not a podcast")
    }

    func testMissingStoredDurationIsCorrected() {
        // The reported case: feed said "1m" for a 2:19 trailer.
        let result = EpisodeDurationCorrector.correction(current: 60, calculated: 139)
        XCTAssertEqual(result?.duration, 139)
        XCTAssertEqual(result?.syncFlag, true)
    }

    func testPlausibleStoredDurationStillAllowsRemoteProbe() {
        var episode = Episode()
        episode.duration = 60
        episode.downloadUrl = "https://example.com/trailer.mp3"

        XCTAssertEqual(EpisodeDurationCorrector.remoteProbeURL(for: episode)?.absoluteString, episode.downloadUrl)
    }

    func testRemoteProbeRejectsNonNetworkURLs() {
        var episode = Episode()
        episode.downloadUrl = "file:///tmp/episode.mp3"

        XCTAssertNil(EpisodeDurationCorrector.remoteProbeURL(for: episode))
    }

    func testProbeCoordinatorCoalescesAndAppliesCooldown() async {
        let coordinator = EpisodeDurationProbeCoordinator(cooldown: 60)
        let start = Date(timeIntervalSince1970: 1_000)

        let firstAdmission = await coordinator.begin(episodeUuid: "episode", now: start)
        let overlappingAdmission = await coordinator.begin(episodeUuid: "episode", now: start)
        XCTAssertTrue(firstAdmission)
        XCTAssertFalse(overlappingAdmission, "an in-flight probe must be coalesced")

        await coordinator.finish(episodeUuid: "episode", now: start)
        let cooldownAdmission = await coordinator.begin(episodeUuid: "episode", now: start.addingTimeInterval(59))
        let afterCooldownAdmission = await coordinator.begin(episodeUuid: "episode", now: start.addingTimeInterval(60))
        XCTAssertFalse(cooldownAdmission)
        XCTAssertTrue(afterCooldownAdmission)
    }
}
