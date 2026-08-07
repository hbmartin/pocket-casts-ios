import XCTest
@testable import podcasts

final class OpmlImportStateTests: XCTestCase {
    func testWholeChunkFailureIsCounted() {
        let state = OpmlImportState()

        state.recordChunkFailure()

        XCTAssertEqual(state.failureCount, 1)
    }

    func testConcurrentResponseAndProgressUpdatesAreAtomic() async {
        let state = OpmlImportState()
        let updateCount = 100

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<updateCount {
                group.addTask {
                    state.recordResponse(
                        pollUuids: ["poll-\(index)"],
                        failedCount: 1
                    )
                    _ = state.updateProgress(failed: true)
                }
            }
        }

        let pollUuids = state.takePollUuids()
        XCTAssertEqual(Set(pollUuids ?? []), Set((0..<updateCount).map { "poll-\($0)" }))
        XCTAssertNil(state.takePollUuids())
        XCTAssertEqual(state.updateProgress(), updateCount + 1)
        XCTAssertEqual(state.failureCount, updateCount * 2)
    }

    func testTerminalFailureRejectsDelayedResponsesAndPolling() {
        let state = OpmlImportState()
        state.markTerminalFailure()

        XCTAssertFalse(state.recordResponse(pollUuids: ["late-poll"], failedCount: 0))
        XCTAssertFalse(state.shouldContinue)
        XCTAssertFalse(state.hasPendingPollUuids)
        XCTAssertNil(state.takePollUuids())
    }
}
