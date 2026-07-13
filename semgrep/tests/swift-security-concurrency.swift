import AVFoundation
import Combine
import Foundation
import MediaPlayer
import UserNotifications
import UIKit

// ruleid: pocketcasts.unchecked-sendable-lazy-dispatch-group
class UnsafeLazyDispatchGroupTask: Operation, @unchecked Sendable { // @unchecked Sendable: fixture for the lazy-dispatch-group rule.
    private lazy var dispatchGroup: DispatchGroup = {
        DispatchGroup()
    }()
}

class SafeDispatchGroupTask: Operation, @unchecked Sendable { // @unchecked Sendable: fixture for the lazy-dispatch-group rule.
    // ok: pocketcasts.unchecked-sendable-lazy-dispatch-group
    private let dispatchGroup = DispatchGroup()
}

class UnsafeApiTaskDispatchGroupWait: ApiBaseTask, @unchecked Sendable { // @unchecked Sendable: fixture for the dispatch-group-wait rule.
    func waitForEpisodes(dispatchGroup: DispatchGroup) {
        // ruleid: pocketcasts.dispatch-group-wait-without-timeout
        dispatchGroup.wait()
    }
}

class SafeApiTaskDispatchGroupWait: ApiBaseTask, @unchecked Sendable { // @unchecked Sendable: fixture for the dispatch-group-wait rule.
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

actor YieldPollingWaiter {
    private var operationIsRunning = true

    func waitForCompletion() async {
        // ruleid: pocketcasts.no-task-yield-polling-loop
        while operationIsRunning {
            await Task.yield()
        }
    }
}

actor ContinuationWaiter {
    private var operationIsRunning = true
    private var waiters = [CheckedContinuation<Void, Never>]()

    func waitForCompletion() async {
        guard operationIsRunning else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
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
            loadMetadata()
        }
    }

    // ok: pocketcasts.avfileutil-unstored-task
    func startsStoredTask() {
        metadataTask = Task {
            loadMetadata()
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

// Combine Subject.send(_:) from inside an unstructured Task closure in an @unchecked Sendable class
// (FileLog's shape): the class opts out of isolation checking and the Task inherits no isolation, so
// publishing races with other Tasks and delivers on an arbitrary executor. The send belongs on an
// actor instead.
final class LogPublisher: @unchecked Sendable {
    private let messageSubject = PassthroughSubject<String, Never>()
    private let valueSubject = CurrentValueSubject<Int, Never>(0)

    func appendsOffActor(_ message: String) {
        Task {
            await self.persist(message)
            // ruleid: pocketcasts.no-subject-send-in-task
            messageSubject.send(message)
        }
    }

    func appendsOffActorWithCapture(_ message: String) {
        Task { [weak self] in
            // ruleid: pocketcasts.no-subject-send-in-task
            self?.messageSubject.send(message)
        }
    }

    func sendsValueOffActor(_ value: Int) {
        Task {
            // ruleid: pocketcasts.no-subject-send-in-task
            valueSubject.send(value)
        }
    }

    // A MainActor-isolated Task makes the send safe, but Semgrep cannot see the isolation, so the
    // rule over-flags it. This pins that known behavior; real code suppresses it with nosemgrep.
    func publishesOnMainActor(_ message: String) {
        Task { @MainActor in
            // ruleid: pocketcasts.no-subject-send-in-task
            messageSubject.send(message)
        }
    }

    func publishesSynchronously(_ message: String) {
        // ok: pocketcasts.no-subject-send-in-task
        messageSubject.send(message)
    }

    private func persist(_ message: String) async {}
}

func sendsOnNonSubjectInTask(socket: TestSocket, data: Data) {
    Task {
        // ok: pocketcasts.no-subject-send-in-task
        socket.send(data)
    }
}

struct TestSocket {
    func send(_ data: Data) {}
}

// A `Task { }` created inside an actor method inherits the actor's isolation, so the send is
// serialized on the actor's executor — the safe pattern. The rule must not flag it.
actor MetadataLoader {
    private let updatesSubject = PassthroughSubject<Int, Never>()

    func load(_ value: Int) {
        Task {
            await self.compute(value)
            // ok: pocketcasts.no-subject-send-in-task
            updatesSubject.send(value)
        }
    }

    private func compute(_ value: Int) async {}
}

func mediaItemArtworkHandlers(image: UIImage) {
    // ruleid: pocketcasts.media-item-artwork-handler-must-be-sendable
    _ = MPMediaItemArtwork(boundsSize: image.size, requestHandler: { _ in image })

    // ok: pocketcasts.media-item-artwork-handler-must-be-sendable
    _ = MPMediaItemArtwork(boundsSize: image.size, requestHandler: { @Sendable _ in image })

    // ruleid: pocketcasts.media-item-artwork-handler-must-be-sendable
    _ = MPMediaItemArtwork(boundsSize: image.size) { _ in image }

    // ok: pocketcasts.media-item-artwork-handler-must-be-sendable
    _ = MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
}

final class AudioSessionObserverFixtures: NSObject {
    func selectorObserver(notificationCenter: NotificationCenter) {
        // ruleid: pocketcasts.av-audio-session-observer-must-use-main-queue
        notificationCenter.addObserver(self, selector: #selector(routeChanged), name: AVAudioSession.routeChangeNotification, object: nil)
    }

    func nilQueueObserver(notificationCenter: NotificationCenter) {
        // ruleid: pocketcasts.av-audio-session-observer-must-use-main-queue
        _ = notificationCenter.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { _ in }
    }

    func mainQueueObserver(notificationCenter: NotificationCenter) {
        // ok: pocketcasts.av-audio-session-observer-must-use-main-queue
        _ = notificationCenter.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { _ in }
    }

    @objc private func routeChanged() {}
}


// MARK: - no-bare-print (Item 55)

func logsSomething(value: Int) {
    // ruleid: pocketcasts.no-bare-print
    print("value is \(value)")
}

struct DemoView_Previews: PreviewProvider {
    static var previews: some View {
        Button("Tap Me") {
            // ok: pocketcasts.no-bare-print
            print("Tapped")
        }
    }
}
