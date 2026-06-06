import Foundation
import UserNotifications

// ruleid: pocketcasts.unchecked-sendable-lazy-dispatch-group
class UnsafeLazyDispatchGroupTask: Operation, @unchecked Sendable {
    private lazy var dispatchGroup: DispatchGroup = {
        DispatchGroup()
    }()
}

class SafeDispatchGroupTask: Operation, @unchecked Sendable {
    // ok: pocketcasts.unchecked-sendable-lazy-dispatch-group
    private let dispatchGroup = DispatchGroup()
}

func clearsBadgeWithTransientValue(notificationCenter: UNUserNotificationCenter) {
    // ruleid: pocketcasts.badge-transient-clear-notifications
    notificationCenter.setBadgeCount(1) {
        notificationCenter.setBadgeCount(0)
    }
}

func clearsBadgeExplicitly(notificationCenter: UNUserNotificationCenter) {
    // ok: pocketcasts.badge-transient-clear-notifications
    notificationCenter.removeAllDeliveredNotifications()
    notificationCenter.setBadgeCount(0)
}

class AVFileUtil: NSObject {
    func startsUnstoredTask() {
        // ruleid: pocketcasts.avfileutil-unstored-task
        Task {
            print("metadata")
        }
    }

    // ok: pocketcasts.avfileutil-unstored-task
    func startsStoredTask() {
        metadataTask = Task {
            print("metadata")
        }
    }

    private var metadataTask: Task<Void, Never>?
}
