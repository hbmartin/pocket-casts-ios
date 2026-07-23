import Foundation
import XCTest

@testable import podcasts

private actor ControlledAssetRequester {
    private var calls = 0
    private var pending: [CheckedContinuation<Bool, Never>] = []
    private var callWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func request() async -> Bool {
        calls += 1
        let readyWaiters = callWaiters.filter { calls >= $0.count }
        callWaiters.removeAll { calls >= $0.count }
        readyWaiters.forEach { $0.continuation.resume() }
        return await withCheckedContinuation { continuation in
            pending.append(continuation)
        }
    }

    func waitForCallCount(_ count: Int) async {
        guard calls < count else { return }
        await withCheckedContinuation { continuation in
            callWaiters.append((count, continuation))
        }
    }

    func completeNext(with result: Bool) {
        pending.removeFirst().resume(returning: result)
    }

    var callCount: Int {
        calls
    }
}

private actor AssetRequestHarness {
    let gate = ContextualEmbeddingAssetRequestGate()
    let requester = ControlledAssetRequester()

    func ready() async -> Bool {
        switch await gate.admission() {
        case .result(let result):
            return result
        case .leader(let requestID):
            let result = await requester.request()
            await gate.complete(requestID: requestID, assetsAvailable: result)
            return result
        }
    }

    func waitForWaitingCallers(_ count: Int) async {
        while await gate.waitingCallerCount < count {
            await Task.yield()
        }
    }
}

final class ContextualEmbeddingProviderTests: XCTestCase {
    func testConcurrentAssetRequestsShareOneInFlightRequest() async {
        let harness = AssetRequestHarness()
        let first = Task { await harness.ready() }
        await harness.requester.waitForCallCount(1)

        let followers = (0 ..< 4).map { _ in Task { await harness.ready() } }
        await harness.waitForWaitingCallers(followers.count)

        let callsBeforeCompletion = await harness.requester.callCount
        XCTAssertEqual(callsBeforeCompletion, 1)
        await harness.requester.completeNext(with: true)

        let firstResult = await first.value
        XCTAssertTrue(firstResult)
        for follower in followers {
            let followerResult = await follower.value
            XCTAssertTrue(followerResult)
        }
        let cachedResult = await harness.ready()
        let finalCallCount = await harness.requester.callCount
        XCTAssertTrue(cachedResult, "a successful request is cached")
        XCTAssertEqual(finalCallCount, 1)
    }

    func testUnavailableAssetRequestIsRememberedForTheLaunch() async {
        let harness = AssetRequestHarness()
        let first = Task { await harness.ready() }
        await harness.requester.waitForCallCount(1)
        await harness.requester.completeNext(with: false)
        let firstResult = await first.value
        XCTAssertFalse(firstResult)

        let cachedResult = await harness.ready()
        let finalCallCount = await harness.requester.callCount
        XCTAssertFalse(cachedResult)
        XCTAssertEqual(finalCallCount, 1)
    }

    func testCancelledLeaderDoesNotStrandFollowersOrPoisonCache() async {
        let harness = AssetRequestHarness()
        let leader = Task { await harness.ready() }
        await harness.requester.waitForCallCount(1)

        let follower = Task { await harness.ready() }
        await harness.waitForWaitingCallers(1)
        leader.cancel()
        await harness.requester.completeNext(with: true)

        let leaderResult = await leader.value
        let followerResult = await follower.value
        let cachedResult = await harness.ready()
        let finalCallCount = await harness.requester.callCount
        XCTAssertTrue(leaderResult)
        XCTAssertTrue(followerResult)
        XCTAssertTrue(cachedResult)
        XCTAssertEqual(finalCallCount, 1)
    }
}
