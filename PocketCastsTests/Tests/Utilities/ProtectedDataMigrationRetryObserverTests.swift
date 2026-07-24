import Foundation
import Testing

@testable import podcasts

private final class RecordingNotificationCenter: NotificationCenter {
    private(set) var removeObserverCallCount = 0

    override func removeObserver(_ observer: Any) {
        removeObserverCallCount += 1
        super.removeObserver(observer)
    }
}

@MainActor
struct ProtectedDataMigrationRetryObserverTests {
    private let notificationName = Notification.Name("ProtectedDataMigrationRetryObserverTests.available")

    // The handler arrives through a main-actor Task hop, so the test awaits the
    // handler's own signal; the time limit turns a lost notification into a
    // failure instead of a hung suite.
    @Test("Protected-data availability schedules the deferred migration retry", .timeLimit(.minutes(1)))
    func protectedDataAvailabilityInvokesHandler() async {
        let notificationCenter = NotificationCenter()

        var observer: ProtectedDataMigrationRetryObserver?
        await withCheckedContinuation { (handlerInvoked: CheckedContinuation<Void, Never>) in
            observer = ProtectedDataMigrationRetryObserver(
                notificationCenter: notificationCenter,
                notificationName: notificationName,
                handler: { handlerInvoked.resume() }
            )
            observer?.start()
            notificationCenter.post(name: notificationName, object: nil)
        }
        withExtendedLifetime(observer) {}
    }

    @Test("Deallocating the observer removes its observation from the center")
    func deinitRemovesObservation() {
        let notificationCenter = RecordingNotificationCenter()

        var observer: ProtectedDataMigrationRetryObserver? = ProtectedDataMigrationRetryObserver(
            notificationCenter: notificationCenter,
            notificationName: notificationName,
            handler: {}
        )
        observer?.start()
        #expect(notificationCenter.removeObserverCallCount == 0)

        observer = nil
        #expect(notificationCenter.removeObserverCallCount == 1)
    }
}
