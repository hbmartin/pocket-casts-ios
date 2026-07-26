import Synchronization
import XCTest

@testable import podcasts

/// A deterministic stand-in for the Foundation Models generation call. Selected
/// invocations suspend on continuations that intentionally ignore cancellation,
/// matching the provider behavior that motivated the admission-control fix.
private actor ControlledGenerationProvider {
    struct Snapshot: Sendable {
        let startCount: Int
        let activeCount: Int
        let maximumActiveCount: Int
    }

    private let blockedInvocations: Set<Int>
    private var startCount = 0
    private var activeCount = 0
    private var maximumActiveCount = 0
    private var finishCount = 0
    private var releaseContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var finishWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(blockedInvocations: Set<Int> = [1]) {
        self.blockedInvocations = blockedInvocations
    }

    func generate() async -> Int {
        startCount += 1
        let invocation = startCount
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        resumeSatisfiedStartWaiters()

        if blockedInvocations.contains(invocation) {
            await withCheckedContinuation { continuation in
                releaseContinuations[invocation] = continuation
            }
        }

        activeCount -= 1
        finishCount += 1
        resumeSatisfiedFinishWaiters()
        return invocation
    }

    func waitUntilStarted(_ expectedCount: Int) async {
        guard startCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((expectedCount, continuation))
        }
    }

    func waitUntilFinished(_ expectedCount: Int) async {
        guard finishCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            finishWaiters.append((expectedCount, continuation))
        }
    }

    func release(_ invocation: Int) {
        releaseContinuations.removeValue(forKey: invocation)?.resume()
    }

    func snapshot() -> Snapshot {
        Snapshot(
            startCount: startCount,
            activeCount: activeCount,
            maximumActiveCount: maximumActiveCount
        )
    }

    private func resumeSatisfiedStartWaiters() {
        let satisfied = startWaiters.filter { $0.count <= startCount }
        startWaiters.removeAll { $0.count <= startCount }
        for waiter in satisfied {
            waiter.continuation.resume()
        }
    }

    private func resumeSatisfiedFinishWaiters() {
        let satisfied = finishWaiters.filter { $0.count <= finishCount }
        finishWaiters.removeAll { $0.count <= finishCount }
        for waiter in satisfied {
            waiter.continuation.resume()
        }
    }
}

/// Contract tests for the timeout primitive and actor-owned admission gate that
/// bound Foundation Models generation (review finding P2-14). Callers resume at
/// the deadline even when work ignores cancellation, while retries stay blocked
/// until that abandoned work actually exits.
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

    private static func startGeneration(
        intelligence: OnDeviceIntelligence,
        provider: ControlledGenerationProvider
    ) -> Task<Int, Error> {
        Task.detached {
            try await intelligence.performGeneration {
                await provider.generate()
            }
        }
    }

    private func assertTimedOut(
        _ task: Task<Int, Error>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await task.value
            XCTFail("Expected .timedOut", file: file, line: line)
        } catch {
            guard case IntelligenceError.timedOut = error else {
                XCTFail("Expected .timedOut, got \(error)", file: file, line: line)
                return
            }
        }
    }

    private func assertConcurrentRequest(
        _ error: any Error,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard Self.isConcurrentRequest(error) else {
            XCTFail("Expected concurrent_requests, got \(error)", file: file, line: line)
            return
        }
    }

    private static func isConcurrentRequest(_ error: any Error) -> Bool {
        guard case IntelligenceError.generationFailed(let description) = error else { return false }
        return description == "concurrent_requests"
    }

    private func performAfterAdmissionReopens(
        intelligence: OnDeviceIntelligence,
        provider: ControlledGenerationProvider
    ) async throws -> Int {
        for _ in 0 ..< 100 {
            do {
                return try await intelligence.performGeneration {
                    await provider.generate()
                }
            } catch where Self.isConcurrentRequest(error) {
                // The provider has returned; allow the completion task's actor
                // hop to clear admission without introducing a wall-clock delay.
                await Task.yield()
            }
        }

        XCTFail("Admission did not reopen after the underlying provider returned")
        return -1
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

    func testTimedOutGenerationRejectsRetryUntilUnderlyingWorkExits() async {
        let intelligence = OnDeviceIntelligence(timeout: .milliseconds(100))
        let provider = ControlledGenerationProvider()
        let first = Self.startGeneration(intelligence: intelligence, provider: provider)
        await provider.waitUntilStarted(1)

        await assertTimedOut(first)

        do {
            _ = try await intelligence.performGeneration {
                await provider.generate()
            }
            XCTFail("Retry must be rejected while timed-out provider work remains active")
        } catch {
            assertConcurrentRequest(error)
        }

        let snapshot = await provider.snapshot()
        XCTAssertEqual(snapshot.startCount, 1, "a rejected retry must not invoke the provider")
        XCTAssertEqual(snapshot.activeCount, 1)

        await provider.release(1)
        await provider.waitUntilFinished(1)
    }

    func testAdmissionBoundsConcurrentCallsToOneProviderGeneration() async throws {
        let intelligence = OnDeviceIntelligence(timeout: .seconds(30))
        let provider = ControlledGenerationProvider()
        let first = Self.startGeneration(intelligence: intelligence, provider: provider)
        await provider.waitUntilStarted(1)

        do {
            _ = try await intelligence.performGeneration {
                await provider.generate()
            }
            XCTFail("A concurrent call must be rejected")
        } catch {
            assertConcurrentRequest(error)
        }

        let snapshot = await provider.snapshot()
        XCTAssertEqual(snapshot.startCount, 1)
        XCTAssertEqual(snapshot.activeCount, 1)
        XCTAssertEqual(snapshot.maximumActiveCount, 1)

        await provider.release(1)
        let firstValue = try await first.value
        XCTAssertEqual(firstValue, 1)
    }

    func testAdmissionRecoversAfterTimedOutUnderlyingWorkCompletes() async throws {
        let intelligence = OnDeviceIntelligence(timeout: .milliseconds(100))
        let provider = ControlledGenerationProvider()
        let first = Self.startGeneration(intelligence: intelligence, provider: provider)
        await provider.waitUntilStarted(1)
        await assertTimedOut(first)

        await provider.release(1)
        await provider.waitUntilFinished(1)

        let recovered = try await performAfterAdmissionReopens(
            intelligence: intelligence,
            provider: provider
        )

        XCTAssertEqual(recovered, 2)
        let snapshot = await provider.snapshot()
        XCTAssertEqual(snapshot.startCount, 2)
        XCTAssertEqual(snapshot.maximumActiveCount, 1)
    }

    func testWatchdogOutlivesCallerTimeoutAndReportsOnce() async {
        let reportCount = Mutex(0)
        let intelligence = OnDeviceIntelligence(
            timeout: .milliseconds(50),
            watchdogReporter: { reportCount.withLock { $0 += 1 } }
        )
        let provider = ControlledGenerationProvider()
        let generation = Self.startGeneration(intelligence: intelligence, provider: provider)
        await provider.waitUntilStarted(1)

        await assertTimedOut(generation)
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(reportCount.withLock { $0 }, 1)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(reportCount.withLock { $0 }, 1)

        await provider.release(1)
        await provider.waitUntilFinished(1)
    }

    func testWatchdogIsCancelledWhenGenerationFinishes() async throws {
        let reportCount = Mutex(0)
        let intelligence = OnDeviceIntelligence(
            timeout: .milliseconds(100),
            watchdogReporter: { reportCount.withLock { $0 += 1 } }
        )
        let provider = ControlledGenerationProvider(blockedInvocations: [])

        let value = try await intelligence.performGeneration {
            await provider.generate()
        }
        try? await Task.sleep(for: .milliseconds(250))

        XCTAssertEqual(value, 1)
        XCTAssertEqual(reportCount.withLock { $0 }, 0)
    }

    func testCallerCancellationReturnsWithoutAdmittingAReplacement() async {
        let intelligence = OnDeviceIntelligence(timeout: .seconds(30))
        let provider = ControlledGenerationProvider()
        let first = Self.startGeneration(intelligence: intelligence, provider: provider)
        await provider.waitUntilStarted(1)

        first.cancel()
        do {
            _ = try await first.value
            XCTFail("A cancelled caller must not produce a value")
        } catch {
            XCTAssertTrue(error is CancellationError, "expected CancellationError, got \(error)")
        }

        do {
            _ = try await intelligence.performGeneration {
                await provider.generate()
            }
            XCTFail("Cancellation-ignoring provider work must retain admission")
        } catch {
            assertConcurrentRequest(error)
        }

        await provider.release(1)
        await provider.waitUntilFinished(1)
    }
}
