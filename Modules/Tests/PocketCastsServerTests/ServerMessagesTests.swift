@testable import PocketCastsServer
import XCTest

/// Round-trip tests for the server-domain typed notification messages
/// (migration Phase 5.5). The bridged representations are frozen while
/// string-based posters/observers still exist, so these assert the exact raw
/// names and `object`/`userInfo` shapes as well as the typed round trip.
///
/// @MainActor because `MainActorMessage`'s bridging requirements are
/// main-actor-isolated.
@MainActor
final class ServerMessagesTests: XCTestCase {
    // MARK: - Raw-name ABI pins

    /// The raw strings are ABI shared with every past app version (and, for
    /// some, other posters). They must never change — including for messages
    /// whose `ServerNotifications` constant has been deleted.
    func testRawNamesArePinned() {
        XCTAssertEqual(SyncStarted.name.rawValue, "PCSyncStarted")
        XCTAssertEqual(SyncCompleted.name.rawValue, "PCSyncDone")
        XCTAssertEqual(SyncFailed.name.rawValue, "PCSyncFailed")
        XCTAssertEqual(SyncProgressPodcastCountKnown.name.rawValue, "PCSyncCount")
        XCTAssertEqual(SyncProgressPodcastUptoChanged.name.rawValue, "PCSyncUpto")
        XCTAssertEqual(SyncProgressPodcastsImported.name.rawValue, "PCSyncPodcastsDone")
        XCTAssertEqual(PodcastsRefreshed.name.rawValue, "PCRefreshed")
        XCTAssertEqual(PodcastRefreshFailed.name.rawValue, "PCRefFailed")
        XCTAssertEqual(PodcastRefreshThrottled.name.rawValue, "PCRefreshedThrottled")
        XCTAssertEqual(EpisodeTypeOrLengthChanged.name.rawValue, "SJEpisodeTypeChanged")
        XCTAssertEqual(SubscriptionStatusChanged.name.rawValue, "SJSubscriptionStatusChanged")
        XCTAssertEqual(UserWillBeSignedOut.name.rawValue, "Server.User.WillBeSignedOut")
    }

    // MARK: - SyncProgressPodcastCountKnown (count payload)

    func testPodcastCountKnownRoundTripsCount() throws {
        let notification = SyncProgressPodcastCountKnown.makeNotification(SyncProgressPodcastCountKnown(count: 42))

        // Frozen bridged shape: the count rides in `object` as an Int/NSNumber.
        XCTAssertEqual(notification.name.rawValue, "PCSyncCount")
        XCTAssertEqual(notification.object as? Int, 42)
        XCTAssertNil(notification.userInfo)

        let roundTripped = try XCTUnwrap(SyncProgressPodcastCountKnown.makeMessage(notification))
        XCTAssertEqual(roundTripped.count, 42)
    }

    func testPodcastCountKnownBridgesFromLegacyNSNumberPost() throws {
        // Legacy string-based posts carry the count boxed as NSNumber.
        let notification = Notification(name: SyncProgressPodcastCountKnown.name, object: NSNumber(value: 7), userInfo: nil)

        let message = try XCTUnwrap(SyncProgressPodcastCountKnown.makeMessage(notification))
        XCTAssertEqual(message.count, 7)
    }

    func testPodcastCountKnownIgnoresPayloadFreePost() {
        XCTAssertNil(SyncProgressPodcastCountKnown.makeMessage(Notification(name: SyncProgressPodcastCountKnown.name)))
    }

    // MARK: - SyncProgressPodcastUptoChanged (position payload)

    func testPodcastUptoChangedRoundTripsPosition() throws {
        let notification = SyncProgressPodcastUptoChanged.makeNotification(SyncProgressPodcastUptoChanged(upTo: 13))

        // Frozen bridged shape: the position rides in `object` as an Int/NSNumber.
        XCTAssertEqual(notification.name.rawValue, "PCSyncUpto")
        XCTAssertEqual(notification.object as? Int, 13)
        XCTAssertNil(notification.userInfo)

        let roundTripped = try XCTUnwrap(SyncProgressPodcastUptoChanged.makeMessage(notification))
        XCTAssertEqual(roundTripped.upTo, 13)
    }

    func testPodcastUptoChangedBridgesFromLegacyNSNumberPost() throws {
        let notification = Notification(name: SyncProgressPodcastUptoChanged.name, object: NSNumber(value: 3), userInfo: nil)

        let message = try XCTUnwrap(SyncProgressPodcastUptoChanged.makeMessage(notification))
        XCTAssertEqual(message.upTo, 3)
    }

    // MARK: - EpisodeTypeOrLengthChanged (uuid payload)

    func testEpisodeTypeOrLengthChangedRoundTripsUuid() throws {
        let notification = EpisodeTypeOrLengthChanged.makeNotification(EpisodeTypeOrLengthChanged(uuid: "episode-uuid"))

        // Frozen bridged shape: the episode uuid rides in `object`.
        XCTAssertEqual(notification.name, ServerNotifications.episodeTypeOrLengthChanged)
        XCTAssertEqual(notification.object as? String, "episode-uuid")

        let roundTripped = try XCTUnwrap(EpisodeTypeOrLengthChanged.makeMessage(notification))
        XCTAssertEqual(roundTripped.uuid, "episode-uuid")
    }

    func testEpisodeTypeOrLengthChangedBridgesFromBareStringPost() throws {
        // A legacy post with no object must still produce a message with a nil
        // uuid (string observers treated that as "re-query everything").
        let message = try XCTUnwrap(EpisodeTypeOrLengthChanged.makeMessage(Notification(name: EpisodeTypeOrLengthChanged.name)))
        XCTAssertNil(message.uuid)
    }

    // MARK: - UserWillBeSignedOut (userInitiated payload)

    func testUserWillBeSignedOutRoundTripsUserInitiated() throws {
        for userInitiated in [true, false] {
            let message = UserWillBeSignedOut(userInitiated: userInitiated)
            let notification = UserWillBeSignedOut.makeNotification(message)

            // Frozen bridged shape: the flag rides in `userInfo["user_initiated"]`.
            XCTAssertEqual(notification.name.rawValue, "Server.User.WillBeSignedOut")
            XCTAssertNil(notification.object)
            XCTAssertEqual(notification.userInfo?["user_initiated"] as? Bool, userInitiated)

            let roundTripped = try XCTUnwrap(UserWillBeSignedOut.makeMessage(notification))
            XCTAssertEqual(roundTripped.userInitiated, userInitiated)
        }
    }

    func testUserWillBeSignedOutIgnoresPayloadFreePost() {
        // The legacy observers guarded on the flag and bailed when it was
        // missing; the typed bridge preserves that by producing no message.
        XCTAssertNil(UserWillBeSignedOut.makeMessage(Notification(name: UserWillBeSignedOut.name)))
    }

    // MARK: - No-payload messages

    func testNoPayloadMessagesBridgeBothWays() {
        // String posts from unconverted files must reach typed observers...
        XCTAssertNotNil(SyncStarted.makeMessage(Notification(name: SyncStarted.name)))
        XCTAssertNotNil(SyncCompleted.makeMessage(Notification(name: ServerNotifications.syncCompleted)))
        XCTAssertNotNil(SyncFailed.makeMessage(Notification(name: SyncFailed.name)))
        XCTAssertNotNil(SyncProgressPodcastsImported.makeMessage(Notification(name: SyncProgressPodcastsImported.name)))
        XCTAssertNotNil(PodcastsRefreshed.makeMessage(Notification(name: ServerNotifications.podcastsRefreshed)))
        XCTAssertNotNil(PodcastRefreshFailed.makeMessage(Notification(name: PodcastRefreshFailed.name)))
        XCTAssertNotNil(PodcastRefreshThrottled.makeMessage(Notification(name: PodcastRefreshThrottled.name)))
        XCTAssertNotNil(SubscriptionStatusChanged.makeMessage(Notification(name: ServerNotifications.subscriptionStatusChanged)))

        // ...and typed posts must keep the legacy raw names for string observers.
        XCTAssertEqual(SyncStarted.makeNotification(SyncStarted()).name, SyncStarted.name)
        XCTAssertEqual(SyncCompleted.makeNotification(SyncCompleted()).name, ServerNotifications.syncCompleted)
        XCTAssertEqual(SyncFailed.makeNotification(SyncFailed()).name, SyncFailed.name)
        XCTAssertEqual(SyncProgressPodcastsImported.makeNotification(SyncProgressPodcastsImported()).name, SyncProgressPodcastsImported.name)
        XCTAssertEqual(PodcastsRefreshed.makeNotification(PodcastsRefreshed()).name, ServerNotifications.podcastsRefreshed)
        XCTAssertEqual(PodcastRefreshFailed.makeNotification(PodcastRefreshFailed()).name, PodcastRefreshFailed.name)
        XCTAssertEqual(PodcastRefreshThrottled.makeNotification(PodcastRefreshThrottled()).name, PodcastRefreshThrottled.name)
        XCTAssertEqual(SubscriptionStatusChanged.makeNotification(SubscriptionStatusChanged()).name, ServerNotifications.subscriptionStatusChanged)
    }
}
