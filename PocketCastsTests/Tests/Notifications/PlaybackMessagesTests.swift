import PocketCastsUtils
import XCTest

@testable import podcasts

/// Round-trip tests for the typed playback messages (migration Phase 5.2):
/// each message must bridge to a `Notification` that string-based observers
/// understand (legacy raw name, frozen payload shape) and back to an identical
/// typed message, so posters and observers can migrate independently.
@MainActor
final class PlaybackMessagesTests: XCTestCase {
    // MARK: - Uuid-carrying messages

    func testPlaybackPositionSavedRoundTrip() throws {
        XCTAssertEqual(PlaybackPositionSaved.name.rawValue, "SJPlayPosSaved", "raw names are effectively ABI and must never change")

        let uuid = UUID().uuidString
        let notification = PlaybackPositionSaved.makeNotification(PlaybackPositionSaved(uuid: uuid))
        XCTAssertEqual(notification.name, PlaybackPositionSaved.name)
        XCTAssertEqual(notification.object as? String, uuid, "string-based observers read the uuid from object")
        XCTAssertNil(notification.userInfo)

        let message = try XCTUnwrap(PlaybackPositionSaved.makeMessage(notification))
        XCTAssertEqual(message.uuid, uuid)

        // nil uuid round trip (a string post that carried no object)
        let nilMessage = try XCTUnwrap(PlaybackPositionSaved.makeMessage(Notification(name: PlaybackPositionSaved.name)))
        XCTAssertNil(nilMessage.uuid)
    }

    // MARK: - Payload-free messages (raw-name ABI pins + both-way bridging)

    func testPlaybackStartingRoundTrip() throws {
        try assertPayloadFreeRoundTrip(PlaybackStarting.self, expectedRawName: "SJPlaybackStarting")
    }

    func testPlaybackStartedRoundTrip() throws {
        try assertPayloadFreeRoundTrip(PlaybackStarted.self, expectedRawName: "SJPlaybackStart")
    }

    func testPlaybackPausedRoundTrip() throws {
        try assertPayloadFreeRoundTrip(PlaybackPaused.self, expectedRawName: "SJPlaybackPaused")
    }

    func testPlaybackEndedRoundTrip() throws {
        try assertPayloadFreeRoundTrip(PlaybackEnded.self, expectedRawName: "SJPlaybackEnd")
    }

    func testPlaybackFailedRoundTrip() throws {
        try assertPayloadFreeRoundTrip(PlaybackFailed.self, expectedRawName: "playbackFailed")
    }

    func testPlaybackProgressedRoundTrip() throws {
        try assertPayloadFreeRoundTrip(PlaybackProgressed.self, expectedRawName: "SJPlaybackProg")
    }

    func testPlaybackTrackChangedRoundTrip() throws {
        try assertPayloadFreeRoundTrip(PlaybackTrackChanged.self, expectedRawName: "SJTrackChanged")
    }

    func testPlaybackEffectsChangedRoundTrip() throws {
        try assertPayloadFreeRoundTrip(PlaybackEffectsChanged.self, expectedRawName: "SJEffectsChanged")
    }

    func testPodcastChaptersDidUpdateRoundTrip() throws {
        try assertPayloadFreeRoundTrip(PodcastChaptersDidUpdate.self, expectedRawName: "SJChaptersChanged")
    }

    func testPodcastChapterChangedRoundTrip() throws {
        try assertPayloadFreeRoundTrip(PodcastChapterChanged.self, expectedRawName: "SJChapterChanged")
    }

    func testCurrentlyPlayingEpisodeUpdatedRoundTrip() throws {
        try assertPayloadFreeRoundTrip(CurrentlyPlayingEpisodeUpdated.self, expectedRawName: "SJCurrentlyPlayingEpisodeUpdated")
    }

    func testSleepTimerChangedRoundTrip() throws {
        try assertPayloadFreeRoundTrip(SleepTimerChanged.self, expectedRawName: "SJSleepTimerChanged")
    }

    func testVideoPlaybackEngineSwitchedRoundTrip() throws {
        try assertPayloadFreeRoundTrip(VideoPlaybackEngineSwitched.self, expectedRawName: "SJVideoPlaybackEngineSwitched")
    }

    func testAudioTuningDidChangeRoundTrip() throws {
        try assertPayloadFreeRoundTrip(AudioTuningDidChange.self, expectedRawName: "SJAudioTuningDidChange")
    }

    func testSkipTimesChangedRoundTrip() throws {
        try assertPayloadFreeRoundTrip(SkipTimesChanged.self, expectedRawName: "SJSkipTimesChanged")
    }

    func testExtraMediaSessionActionsChangedRoundTrip() throws {
        try assertPayloadFreeRoundTrip(ExtraMediaSessionActionsChanged.self, expectedRawName: "SJMediaSessionActionsChanged")
    }

    func testRemoteCommandSettingsChangedRoundTrip() throws {
        try assertPayloadFreeRoundTrip(RemoteCommandSettingsChanged.self, expectedRawName: "SJRemoteCommandSettingsChanged")
    }

    func testPlayerActionsUpdatedRoundTrip() throws {
        try assertPayloadFreeRoundTrip(PlayerActionsUpdated.self, expectedRawName: "SJPlayerActionsUpdated")
    }

    // MARK: - Helpers

    /// message -> Notification -> message for payload-free names: the bridged
    /// Notification is bare (legacy raw name, no object/userInfo) and any
    /// Notification with the right name decodes to a message.
    private func assertPayloadFreeRoundTrip<M: NotificationCenter.MainActorMessage>(_ type: M.Type, expectedRawName: String) throws {
        XCTAssertEqual(M.name.rawValue, expectedRawName, "raw names are effectively ABI and must never change")

        let message = try XCTUnwrap(M.makeMessage(Notification(name: M.name)))
        let notification = M.makeNotification(message)
        XCTAssertEqual(notification.name, M.name)
        XCTAssertNil(notification.object)

        XCTAssertNotNil(M.makeMessage(notification))
    }
}
