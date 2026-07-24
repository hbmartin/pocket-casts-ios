import Foundation
import Testing

@testable import podcasts

@MainActor
struct ProtectedDataMigrationRetryObserverTests {
    @Test("Protected-data availability schedules the deferred migration retry")
    func protectedDataAvailabilityInvokesHandler() async {
        let notificationCenter = NotificationCenter()
        let notificationName = Notification.Name("ProtectedDataMigrationRetryObserverTests.available")

        await confirmation("Migration retry invoked") { confirm in
            let observer = ProtectedDataMigrationRetryObserver(
                notificationCenter: notificationCenter,
                notificationName: notificationName,
                handler: { confirm() }
            )
            observer.start()
            notificationCenter.post(name: notificationName, object: nil)
            await Task.yield()
            withExtendedLifetime(observer) {}
        }
    }
}
