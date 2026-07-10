import AVFoundation
import XCTest
@testable import podcasts

@MainActor
final class PlaybackManagerNotificationTests: XCTestCase {
    func testAudioSessionNotificationsPostedOffMainAreDeliveredOnMainActor() async {
        let notificationCenter = NotificationCenter()
        let delivered = expectation(description: "All audio session notifications delivered")
        delivered.expectedFulfillmentCount = 3
        var deliveredNames = [Notification.Name]()

        var observers: AudioSessionNotificationObservers? = PlaybackManager.observeAudioSessionNotifications(
            notificationCenter: notificationCenter,
            routeChanged: { notification in
                MainActor.preconditionIsolated()
                deliveredNames.append(notification.name)
                delivered.fulfill()
            },
            audioInterrupted: { notification in
                MainActor.preconditionIsolated()
                deliveredNames.append(notification.name)
                delivered.fulfill()
            },
            mediaServicesReset: { notification in
                MainActor.preconditionIsolated()
                deliveredNames.append(notification.name)
                delivered.fulfill()
            }
        )
        XCTAssertNotNil(observers)

        await Task.detached {
            notificationCenter.post(name: AVAudioSession.routeChangeNotification, object: nil)
            notificationCenter.post(name: AVAudioSession.interruptionNotification, object: nil)
            notificationCenter.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        }.value

        await fulfillment(of: [delivered], timeout: 1)
        XCTAssertEqual(
            Set(deliveredNames),
            [
                AVAudioSession.routeChangeNotification,
                AVAudioSession.interruptionNotification,
                AVAudioSession.mediaServicesWereResetNotification
            ]
        )

        observers = nil
        await Task.detached {
            notificationCenter.post(name: AVAudioSession.routeChangeNotification, object: nil)
            notificationCenter.post(name: AVAudioSession.interruptionNotification, object: nil)
            notificationCenter.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        }.value
        await Task.yield()

        XCTAssertEqual(deliveredNames.count, 3, "Releasing the observer owner should unregister every callback")
    }
}
