import Foundation
import PocketCastsUtils
import XCTest

/// Delivery-semantics tests for the typed `NotificationCenter.postOnMainThread(_:)`
/// helper (the string-name-based variant is retired): observers run on the main
/// thread, the frozen bridged payload shape is what gets posted, and the call
/// blocks until observers have run.
@MainActor
final class NotificationMainThreadTests: XCTestCase {
    func test_message_posts_on_main_thread() {
        expectation(forNotification: TestMessage.name, object: nil) { _ in
            XCTAssertTrue(Thread.isMainThread)
            return true
        }

        DispatchQueue.global(qos: .default).sync {
            NotificationCenter.postOnMainThread(TestMessage(uuid: nil))
        }

        waitForExpectations(timeout: 1)
    }

    func test_message_posts_bridged_uuid_in_object() {
        expectation(forNotification: TestMessage.name, object: nil) { notification in
            XCTAssertEqual(notification.object as? String, "Hello")
            return true
        }

        NotificationCenter.postOnMainThread(TestMessage(uuid: "Hello"))
        waitForExpectations(timeout: 1)
    }

    func test_post_returns_after_observers_ran() {
        let delivered = expectation(forNotification: TestMessage.name, object: nil)

        NotificationCenter.postOnMainThread(TestMessage(uuid: nil))

        // Blocking main-sync semantics: the observer has already run by the time
        // postOnMainThread returns, so a zero timeout must succeed.
        wait(for: [delivered], timeout: 0)
    }
}

private struct TestMessage: UuidBridgedMessage {
    static var name: Notification.Name { Notification.Name("Unit.Testing.Is.Awesome") }

    let uuid: String?

    init(uuid: String?) {
        self.uuid = uuid
    }
}
