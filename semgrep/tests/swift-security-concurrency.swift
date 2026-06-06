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

class UnsafeApiTaskDispatchGroupWait: ApiBaseTask, @unchecked Sendable {
    func waitForEpisodes(dispatchGroup: DispatchGroup) {
        // ruleid: pocketcasts.dispatch-group-wait-without-timeout
        dispatchGroup.wait()
    }
}

class SafeApiTaskDispatchGroupWait: ApiBaseTask, @unchecked Sendable {
    func waitForEpisodes(dispatchGroup: DispatchGroup) {
        // ok: pocketcasts.dispatch-group-wait-without-timeout
        _ = dispatchGroup.wait(timeout: .now() + .seconds(30))
    }
}

class UnsafeApiTaskDispatchGroupWaitWithoutSendable: ApiBaseTask {
    func waitForEpisodes(dispatchGroup: DispatchGroup) {
        // ruleid: pocketcasts.dispatch-group-wait-without-timeout
        dispatchGroup.wait()
    }
}

protocol RetriableApiTask {}

class UnsafeApiTaskDispatchGroupWaitWithProtocol: ApiBaseTask, RetriableApiTask {
    func waitForEpisodes(dispatchGroup: DispatchGroup) {
        // ruleid: pocketcasts.dispatch-group-wait-without-timeout
        dispatchGroup.wait()
    }
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

    func startsStoredTaskWithStrongSelfBeforeAwait() {
        // ruleid: pocketcasts.avfileutil-task-strong-self-before-await
        metadataTask = Task { [weak self] in
            guard let self else { return }
            await self.loadMetadata()
        }
    }

    func startsStoredTaskWithCopiedValues() {
        // ok: pocketcasts.avfileutil-task-strong-self-before-await
        metadataTask = Task { [weak self] in
            guard let asset = self?.asset else { return }
            await asset.loadMetadata()
        }
    }

    private var asset: TestAsset?
    private var metadataTask: Task<Void, Never>?

    private func loadMetadata() async {}
}

class TestAsset {
    func loadMetadata() async {}
}
