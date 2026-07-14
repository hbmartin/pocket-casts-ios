import XCTest

@testable import podcasts

/// Contract tests for `OnDeviceIntelligence.raceAgainstTimeout`, the primitive
/// that bounds Foundation Models generation (review finding P2-14). The critical
/// property: the caller is resumed at the deadline even when the work **ignores
/// cancellation** — the old task-group race awaited its cancelled children, so a
/// hung generation wedged callers indefinitely.
final class OnDeviceIntelligenceRaceTests: XCTestCase {

    /// Suspends forever and never observes cancellation — the worst-case
    /// non-cooperative generation call.
    private static func hangForever() async throws -> Int {
        try await withUnsafeThrowingContinuation { (_: UnsafeContinuation<Int, Error>) in }
    }

    /// Hoisted into a named function: an inline Task-literal race trips a
    /// region-isolation checker limitation ("pattern the checker does not
    /// understand how to check").
    private static func raceAgainstHungWork(timeout: Duration) async throws -> Int {
        try await OnDeviceIntelligence.raceAgainstTimeout(timeout: timeout) {
            try await hangForever()
        }
    }

    /// Same checker limitation: the Task literal must also live outside the
    /// (default-MainActor) test method body.
    private static func startDetachedRace(timeout: Duration) -> Task<Int, Error> {
        Task.detached {
            try await raceAgainstHungWork(timeout: timeout)
        }
    }

    func testWorkValueWinsBeforeTimeout() async throws {
        let value = try await OnDeviceIntelligence.raceAgainstTimeout(timeout: .seconds(30)) {
            42
        }
        XCTAssertEqual(value, 42)
    }

    func testWorkErrorPropagates() async {
        struct WorkError: Error {}
        do {
            _ = try await OnDeviceIntelligence.raceAgainstTimeout(timeout: .seconds(30)) { () -> Int in
                throw WorkError()
            }
            XCTFail("The work's error should propagate")
        } catch {
            XCTAssertTrue(error is WorkError)
        }
    }

    func testTimeoutResumesPromptlyWhenWorkIgnoresCancellation() async {
        let start = Date()
        do {
            _ = try await Self.raceAgainstHungWork(timeout: .milliseconds(150))
            XCTFail("A hung generation must not produce a value")
        } catch {
            guard case IntelligenceError.timedOut = error else {
                XCTFail("Expected .timedOut, got \(error)")
                return
            }
        }
        // The whole point of the primitive: the deadline bounds the caller even
        // though the work never returns. Generous margin for CI scheduling.
        XCTAssertLessThan(Date().timeIntervalSince(start), 5, "the caller must resume at the deadline, not when the hung work finishes")
    }

    func testCooperativeWorkIsCancelledOnTimeout() async {
        let workCancelled = expectation(description: "the losing work observed cancellation")
        do {
            _ = try await OnDeviceIntelligence.raceAgainstTimeout(timeout: .milliseconds(50)) { () -> Int in
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    workCancelled.fulfill()
                    throw error
                }
                return 0
            }
            XCTFail("Expected a timeout")
        } catch {
            guard case IntelligenceError.timedOut = error else {
                XCTFail("Expected .timedOut, got \(error)")
                return
            }
        }
        await fulfillment(of: [workCancelled], timeout: 5)
    }

    func testCallerCancellationEndsTheRaceWithCancellationError() async {
        let raceTask = Self.startDetachedRace(timeout: .seconds(30))
        try? await Task.sleep(for: .milliseconds(100))
        raceTask.cancel()

        do {
            _ = try await raceTask.value
            XCTFail("A cancelled race must not produce a value")
        } catch {
            XCTAssertTrue(error is CancellationError, "expected CancellationError, got \(error)")
        }
    }
}
