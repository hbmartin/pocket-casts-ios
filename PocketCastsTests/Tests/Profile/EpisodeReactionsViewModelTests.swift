import XCTest
import PocketCastsServer
@testable import podcasts

@MainActor
final class EpisodeReactionsViewModelTests: XCTestCase {
    func testTapIgnoresConcurrentReactionMutation() async {
        let gate = ReactionRequestGate()
        let model = EpisodeReactionsViewModel(
            episodeUuid: "episode",
            canReact: true,
            fixture: EpisodeReactions(counts: [:], yourReaction: nil),
            fetchReactions: { _ in nil },
            setReaction: { _, _ in await gate.waitForRelease() }
        )

        let firstTap = Task { await model.tap(.heart) }
        await gate.waitUntilEntered()
        await model.tap(.laugh)
        await gate.release(returning: true)
        await firstTap.value

        let callCount = await gate.callCount
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(model.reactions,
                       EpisodeReactions(counts: [.heart: 1], yourReaction: .heart))
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
}

private actor ReactionRequestGate {
    private(set) var callCount = 0
    private var isEntered = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Bool, Never>?

    func waitForRelease() async -> Bool {
        callCount += 1
        isEntered = true
        enteredWaiters.forEach { $0.resume() }
        enteredWaiters.removeAll()
        return await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilEntered() async {
        guard !isEntered else { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func release(returning result: Bool) {
        releaseContinuation?.resume(returning: result)
        releaseContinuation = nil
    }
}
