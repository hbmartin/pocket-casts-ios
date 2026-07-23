import XCTest
import PocketCastsServer
@testable import podcasts

@MainActor
final class EpisodeReactionsViewModelTests: XCTestCase {
    func testTapWhileMutationInFlightQueuesTheLatestIntent() async {
        let gate = ReactionRequestGate()
        let model = EpisodeReactionsViewModel(
            episodeUuid: "episode",
            canReact: true,
            fixture: EpisodeReactions(counts: [:], yourReaction: nil),
            fetchReactions: { _ in nil },
            setReaction: { _, kind in await gate.waitForRelease(recording: kind) }
        )

        let firstTap = Task { await model.tap(.heart) }
        await gate.waitUntilEntered(count: 1)
        await model.tap(.laugh)

        // The mid-flight tap applies optimistically right away…
        XCTAssertEqual(model.reactions,
                       EpisodeReactions(counts: [.laugh: 1], yourReaction: .laugh))

        // …and is written once the in-flight mutation completes.
        await gate.release(returning: true)
        await gate.waitUntilEntered(count: 2)
        await gate.release(returning: true)
        await firstTap.value

        let requestedKinds = await gate.requestedKinds
        XCTAssertEqual(requestedKinds, [.heart, .laugh])
        XCTAssertEqual(model.reactions,
                       EpisodeReactions(counts: [.laugh: 1], yourReaction: .laugh))
    }

    func testTapRestoresPreviousStateWhenMutationAndRefreshFail() async {
        let previous = EpisodeReactions(counts: [.clap: 3], yourReaction: .clap)
        let model = EpisodeReactionsViewModel(
            episodeUuid: "episode",
            canReact: true,
            fixture: previous,
            fetchReactions: { _ in nil },
            setReaction: { _, _ in false }
        )

        await model.tap(.fire)

        XCTAssertEqual(model.reactions, previous)
    }

    func testLaterFailureFallsBackToSuccessfulIntermediateWriteWhenRefreshFails() async {
        let gate = ReactionRequestGate()
        let model = EpisodeReactionsViewModel(
            episodeUuid: "episode",
            canReact: true,
            fixture: EpisodeReactions(counts: [:], yourReaction: nil),
            fetchReactions: { _ in nil },
            setReaction: { _, kind in await gate.waitForRelease(recording: kind) }
        )

        let firstTap = Task { await model.tap(.heart) }
        await gate.waitUntilEntered(count: 1)
        await model.tap(.laugh)

        await gate.release(returning: true)
        await gate.waitUntilEntered(count: 2)
        await gate.release(returning: false)
        await firstTap.value

        let requestedKinds = await gate.requestedKinds
        XCTAssertEqual(requestedKinds, [.heart, .laugh])
        XCTAssertEqual(
            model.reactions,
            EpisodeReactions(counts: [.heart: 1], yourReaction: .heart),
            "A failed latest write and refresh must fall back to the last server-confirmed write"
        )
    }
}

private actor ReactionRequestGate {
    private(set) var requestedKinds: [ReactionKind?] = []
    private var enteredWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var releaseContinuations: [CheckedContinuation<Bool, Never>] = []

    func waitForRelease(recording kind: ReactionKind?) async -> Bool {
        requestedKinds.append(kind)
        let entered = requestedKinds.count
        for waiter in enteredWaiters where waiter.count <= entered {
            waiter.continuation.resume()
        }
        enteredWaiters.removeAll { $0.count <= entered }
        return await withCheckedContinuation { releaseContinuations.append($0) }
    }

    func waitUntilEntered(count: Int) async {
        guard requestedKinds.count < count else { return }
        await withCheckedContinuation { enteredWaiters.append((count: count, continuation: $0)) }
    }

    func release(returning result: Bool) {
        guard !releaseContinuations.isEmpty else { return }
        releaseContinuations.removeFirst().resume(returning: result)
    }
}
