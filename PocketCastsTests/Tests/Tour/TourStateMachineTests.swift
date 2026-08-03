import XCTest

@testable import podcasts

/// Full transition coverage for the tour reducer (Highlights S9).
final class TourStateMachineTests: XCTestCase {
    private var plan: TourPlan {
        TourPlan(
            stops: [
                TourStop(startTime: 100, endTime: 160, title: "One", bridgeLine: "Next: One"),
                TourStop(startTime: 300, endTime: 400, title: "Two", bridgeLine: "Next: Two"),
                TourStop(startTime: 700, endTime: 800, title: "Three", bridgeLine: "Next: Three")
            ],
            introLine: "Intro",
            outroLine: "Outro"
        )
    }

    private func spokenMachine() -> TourStateMachine {
        TourStateMachine(plan: plan, spokenTransitions: true)
    }

    private func toneMachine() -> TourStateMachine {
        TourStateMachine(plan: plan, spokenTransitions: false)
    }

    // MARK: - Happy path (spoken)

    func testSpokenTourWalksIntroBridgesAndOutro() {
        var machine = spokenMachine()

        XCTAssertEqual(machine.handle(.planReady), [.pauseKeepingSession, .speakIntro, .notifyStateChanged])
        XCTAssertEqual(machine.handle(.speechFinished), [.seek(to: 100, startPlayback: true), .notifyStateChanged])
        XCTAssertEqual(machine.state, .touring(index: 0))

        // Mid-segment ticks do nothing.
        XCTAssertEqual(machine.handle(.tick(time: 130, rate: 1)), [])

        // Segment end → bridge.
        XCTAssertEqual(machine.handle(.tick(time: 159.6, rate: 1)),
                       [.pauseKeepingSession, .speakBridge(nextIndex: 1), .notifyStateChanged])
        XCTAssertEqual(machine.handle(.speechFinished), [.seek(to: 300, startPlayback: true), .notifyStateChanged])

        // Last segment end → outro → finished.
        XCTAssertEqual(machine.handle(.tick(time: 399.9, rate: 1)),
                       [.pauseKeepingSession, .speakBridge(nextIndex: 2), .notifyStateChanged])
        _ = machine.handle(.speechFinished)
        XCTAssertEqual(machine.handle(.tick(time: 800, rate: 1)),
                       [.pauseKeepingSession, .speakOutro, .notifyStateChanged])
        XCTAssertEqual(machine.handle(.speechFinished), [.pauseAtEnd, .notifyFinished, .notifyStateChanged])
        XCTAssertEqual(machine.state, .finished)
    }

    func testToneOnlyTourSeeksWithEarcons() {
        var machine = toneMachine()

        XCTAssertEqual(machine.handle(.planReady),
                       [.seek(to: 100, startPlayback: true), .playEarcon, .notifyStateChanged])
        XCTAssertEqual(machine.handle(.tick(time: 160, rate: 1)),
                       [.seek(to: 300, startPlayback: true), .playEarcon, .notifyStateChanged])
        XCTAssertEqual(machine.state, .touring(index: 1))
    }

    func testSpeechUnavailableFallsBackToEarconJump() {
        var machine = spokenMachine()
        _ = machine.handle(.planReady)

        XCTAssertEqual(machine.handle(.speechUnavailable), [.seek(to: 100, startPlayback: true), .notifyStateChanged])

        _ = machine.handle(.tick(time: 160, rate: 1)) // → bridging(1)
        XCTAssertEqual(machine.handle(.speechUnavailable),
                       [.playEarcon, .seek(to: 300, startPlayback: true), .notifyStateChanged])
    }

    // MARK: - Segment-end tolerance

    func testSegmentEndScalesWithPlaybackRate() {
        var machine = toneMachine()
        _ = machine.handle(.planReady)

        XCTAssertFalse(machine.handle(.tick(time: 158.6, rate: 3)).isEmpty,
                       "at 3x the end threshold widens to 1.5s of wall clock")

        var slow = toneMachine()
        _ = slow.handle(.planReady)
        XCTAssertTrue(slow.handle(.tick(time: 158.6, rate: 1)).isEmpty,
                      "at 1x the same time is still mid-segment")
    }

    // MARK: - External seeks

    func testScrubbingInsideTheStopKeepsTouring() {
        var machine = toneMachine()
        _ = machine.handle(.planReady)

        XCTAssertTrue(machine.handle(.externalSeek(time: 120)).isEmpty)
        XCTAssertEqual(machine.state, .touring(index: 0))
    }

    func testSeekingAwayCancelsSilently() {
        var machine = toneMachine()
        _ = machine.handle(.planReady)

        XCTAssertEqual(machine.handle(.externalSeek(time: 500)), [.notifyStateChanged])
        XCTAssertEqual(machine.state, .cancelled(reason: .userSeeked))
        XCTAssertFalse(machine.isActive)
    }

    func testUnattributedJumpDetectedFromTheTick() {
        var machine = toneMachine()
        _ = machine.handle(.planReady)

        XCTAssertEqual(machine.handle(.tick(time: 600, rate: 1)), [.notifyStateChanged])
        XCTAssertEqual(machine.state, .cancelled(reason: .userSeeked))
    }

    // MARK: - Pause / resume

    func testPauseMidSegmentResumesInPlace() {
        var machine = toneMachine()
        _ = machine.handle(.planReady)

        _ = machine.handle(.userPaused)
        XCTAssertEqual(machine.state, .suspended(resume: .inSegment(index: 0)))

        XCTAssertEqual(machine.handle(.userResumed), [.notifyStateChanged])
        XCTAssertEqual(machine.state, .touring(index: 0))
    }

    func testPauseMidBridgeResumesAtNextStopWithoutReSpeaking() {
        var machine = spokenMachine()
        _ = machine.handle(.planReady)
        _ = machine.handle(.speechFinished)          // touring(0)
        _ = machine.handle(.tick(time: 160, rate: 1)) // bridging(1)

        XCTAssertEqual(machine.handle(.userPaused), [.stopSpeech, .notifyStateChanged])
        XCTAssertEqual(machine.state, .suspended(resume: .atSegmentStart(index: 1)))

        XCTAssertEqual(machine.handle(.userResumed), [.seek(to: 300, startPlayback: true), .notifyStateChanged])
        XCTAssertEqual(machine.state, .touring(index: 1))
    }

    // MARK: - Global exits

    func testEpisodeChangeCancelsFromAnyActiveState() {
        var machine = spokenMachine()
        _ = machine.handle(.planReady) // speakingIntro

        XCTAssertEqual(machine.handle(.episodeChanged), [.stopSpeech, .notifyStateChanged])
        XCTAssertEqual(machine.state, .cancelled(reason: .episodeChanged))

        // Terminal states swallow further events.
        XCTAssertTrue(machine.handle(.tick(time: 160, rate: 1)).isEmpty)
        XCTAssertTrue(machine.handle(.cancelRequested).isEmpty)
    }

    func testPlanFailureReportsAndTerminates() {
        var machine = spokenMachine()
        XCTAssertEqual(machine.handle(.planFailed), [.notifyStateChanged])
        XCTAssertEqual(machine.state, .cancelled(reason: .preparationFailed))
    }
}

/// Budget math for the tour planner (Highlights S9).
final class TourPlannerTests: XCTestCase {
    private func segment(rank: Int, start: TimeInterval, duration: TimeInterval, title: String = "S") -> SalientSegment {
        SalientSegment(rank: rank, startTime: start, endTime: start + duration,
                       title: "\(title)\(rank)", score: 10 - rank, excerpt: "")
    }

    func testGreedyPrefixByRankThenChronological() {
        // Ranks 0..3 at 120s each; Quick budget (300s) fits ranks 0 and 1.
        let segments = [
            segment(rank: 2, start: 100, duration: 120),
            segment(rank: 0, start: 900, duration: 120),
            segment(rank: 1, start: 400, duration: 120),
            segment(rank: 3, start: 1400, duration: 120)
        ]

        let plan = TourPlanner.plan(segments: segments, length: .quick,
                                    episodeDuration: 3600, episodeTitle: "Ep")

        XCTAssertEqual(plan?.stops.map(\.startTime), [400, 900],
                       "top ranks are chosen, then reordered chronologically")
    }

    func testOversizedCandidateIsSkippedNotTruncated() {
        let segments = [
            segment(rank: 0, start: 100, duration: 400), // overflows the 300s Quick budget
            segment(rank: 1, start: 600, duration: 120)
        ]

        let plan = TourPlanner.plan(segments: segments, length: .quick,
                                    episodeDuration: 3600, episodeTitle: "Ep")

        XCTAssertEqual(plan?.stops.map(\.startTime), [600])
    }

    func testAtLeastOneStopSurvivesEvenWhenEverythingOverflows() {
        let segments = [segment(rank: 0, start: 100, duration: 400)]

        let plan = TourPlanner.plan(segments: segments, length: .quick,
                                    episodeDuration: 3600, episodeTitle: "Ep")

        XCTAssertEqual(plan?.stops.count, 1, "the top rank always plays")
    }

    func testNoSegmentsMeansNoPlan() {
        XCTAssertNil(TourPlanner.plan(segments: [], length: .standard,
                                      episodeDuration: 3600, episodeTitle: "Ep"))
    }

    func testBudgetsScaleWithLength() {
        XCTAssertEqual(TourLength.quick.budget(forDuration: 3600), 300)
        XCTAssertEqual(TourLength.quick.budget(forDuration: 480), 240, "short episodes halve")
        XCTAssertEqual(TourLength.standard.budget(forDuration: 3600), 900)
        XCTAssertEqual(TourLength.deep.budget(forDuration: 3600), 1800)
    }
}
