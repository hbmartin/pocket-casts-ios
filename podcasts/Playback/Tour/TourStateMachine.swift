import Foundation

/// Pure reducer for the Highlights Tour (S9). The controller feeds events in
/// and executes the returned effects; nothing here touches the player, the
/// synthesizer, or the clock, so every transition is unit-testable.
nonisolated struct TourStateMachine: Sendable {
    // MARK: - Model

    enum State: Equatable, Sendable {
        case idle
        /// Loading transcript + segments, planning.
        case preparing
        case speakingIntro
        /// Playing stop `index`; segment-end detection runs off the 1 Hz tick.
        case touring(index: Int)
        /// Speaking the bridge before seeking to stop `nextIndex`.
        case bridging(nextIndex: Int)
        case speakingOutro
        case suspended(resume: Resume)
        case finished
        case cancelled(reason: CancelReason)

        enum Resume: Equatable, Sendable {
            /// Paused mid-stop: resume in place.
            case inSegment(index: Int)
            /// Paused mid-bridge/intro: jump straight to the stop (no re-speak).
            case atSegmentStart(index: Int)
        }
    }

    enum CancelReason: Equatable, Sendable {
        case userSeeked
        case episodeChanged
        case userCancelled
        case preparationFailed
    }

    enum Event: Equatable, Sendable {
        case planReady
        case planFailed
        case speechFinished
        /// No voice for the language — fall back to the earcon for this jump.
        case speechUnavailable
        /// The 1 Hz supervisor tick (playback time + rate).
        case tick(time: TimeInterval, rate: Double)
        /// A seek the controller didn't issue (scrubber, skip, remote, sync).
        case externalSeek(time: TimeInterval)
        case userPaused
        case userResumed
        case episodeChanged
        case cancelRequested
    }

    enum Effect: Equatable, Sendable {
        /// Pause WITHOUT the delayed audio-session deactivation (speech is next).
        case pauseKeepingSession
        case seek(to: TimeInterval, startPlayback: Bool)
        case speakIntro
        case speakBridge(nextIndex: Int)
        case speakOutro
        case stopSpeech
        case playEarcon
        case notifyStateChanged
        case notifyFinished
        case pauseAtEnd
    }

    /// How far past a stop's end the playhead may drift (per tick, scaled by
    /// rate) before we treat it as an unattributed external seek.
    static let externalJumpSlop: TimeInterval = 3
    /// Scrubbing this far before the current stop's start also exits the tour.
    static let leadingSlop: TimeInterval = 5

    let plan: TourPlan
    let spokenTransitions: Bool
    private(set) var state: State = .preparing

    init(plan: TourPlan, spokenTransitions: Bool) {
        self.plan = plan
        self.spokenTransitions = spokenTransitions
    }

    var isActive: Bool {
        switch state {
        case .idle, .finished, .cancelled: false
        default: true
        }
    }

    /// The stop relevant to the current state (for the HUD).
    var currentStopIndex: Int? {
        switch state {
        case .touring(let index): index
        case .bridging(let nextIndex): nextIndex
        case .suspended(.inSegment(let index)): index
        case .suspended(.atSegmentStart(let index)): index
        default: nil
        }
    }

    // MARK: - Reduction

    mutating func handle(_ event: Event) -> [Effect] {
        switch (state, event) {
        // Preparation
        case (.preparing, .planReady):
            if spokenTransitions {
                state = .speakingIntro
                return [.pauseKeepingSession, .speakIntro, .notifyStateChanged]
            }
            state = .touring(index: 0)
            return [seekEffect(0), .playEarcon, .notifyStateChanged]

        case (.preparing, .planFailed):
            state = .cancelled(reason: .preparationFailed)
            return [.notifyStateChanged]

        // Intro
        case (.speakingIntro, .speechFinished), (.speakingIntro, .speechUnavailable):
            state = .touring(index: 0)
            return [seekEffect(0), .notifyStateChanged]

        case (.speakingIntro, .userPaused):
            state = .suspended(resume: .atSegmentStart(index: 0))
            return [.stopSpeech, .notifyStateChanged]

        // Touring: segment-end detection + external-seek policing
        case (.touring(let index), .tick(let time, let rate)):
            let stop = plan.stops[index]
            if time > stop.endTime + max(Self.externalJumpSlop, 2 * rate) || time < stop.startTime - Self.leadingSlop {
                state = .cancelled(reason: .userSeeked)
                return [.notifyStateChanged]
            }
            guard time >= stop.endTime - 0.5 * max(rate, 0.1) else { return [] }
            return advance(from: index)

        case (.touring(let index), .externalSeek(let time)):
            let stop = plan.stops[index]
            if time >= stop.startTime - Self.leadingSlop, time <= stop.endTime {
                return [] // scrubbing within the highlight keeps the tour alive
            }
            state = .cancelled(reason: .userSeeked)
            return [.notifyStateChanged]

        case (.touring(let index), .userPaused):
            state = .suspended(resume: .inSegment(index: index))
            return [.notifyStateChanged]

        // Bridging / outro (speech-delegate driven; the tick is stopped)
        case (.bridging(let nextIndex), .speechFinished), (.bridging(let nextIndex), .speechUnavailable):
            state = .touring(index: nextIndex)
            var effects = [seekEffect(nextIndex), .notifyStateChanged]
            if case .speechUnavailable = event { effects.insert(.playEarcon, at: 0) }
            return effects

        case (.bridging(let nextIndex), .userPaused):
            state = .suspended(resume: .atSegmentStart(index: nextIndex))
            return [.stopSpeech, .notifyStateChanged]

        case (.speakingOutro, .speechFinished), (.speakingOutro, .speechUnavailable):
            state = .finished
            return [.pauseAtEnd, .notifyFinished, .notifyStateChanged]

        case (.speakingOutro, .userPaused):
            state = .finished
            return [.stopSpeech, .notifyFinished, .notifyStateChanged]

        // Suspension
        case (.suspended(.inSegment(let index)), .userResumed):
            state = .touring(index: index)
            return [.notifyStateChanged]

        case (.suspended(.atSegmentStart(let index)), .userResumed):
            state = .touring(index: index)
            return [seekEffect(index), .notifyStateChanged]

        case (.suspended, .externalSeek(let time)):
            // A seek while paused: same in/out policy against the resume stop.
            if let index = currentStopIndex {
                let stop = plan.stops[index]
                if time >= stop.startTime - Self.leadingSlop, time <= stop.endTime {
                    state = .suspended(resume: .inSegment(index: index))
                    return []
                }
            }
            state = .cancelled(reason: .userSeeked)
            return [.notifyStateChanged]

        // Global exits
        case (_, .episodeChanged) where isActive:
            state = .cancelled(reason: .episodeChanged)
            return [.stopSpeech, .notifyStateChanged]

        case (_, .cancelRequested) where isActive:
            state = .cancelled(reason: .userCancelled)
            return [.stopSpeech, .notifyStateChanged]

        default:
            return []
        }
    }

    private mutating func advance(from index: Int) -> [Effect] {
        let next = index + 1
        guard next < plan.stops.count else {
            if spokenTransitions {
                state = .speakingOutro
                return [.pauseKeepingSession, .speakOutro, .notifyStateChanged]
            }
            state = .finished
            return [.pauseAtEnd, .notifyFinished, .notifyStateChanged]
        }

        if spokenTransitions {
            state = .bridging(nextIndex: next)
            return [.pauseKeepingSession, .speakBridge(nextIndex: next), .notifyStateChanged]
        }
        state = .touring(index: next)
        return [seekEffect(next), .playEarcon, .notifyStateChanged]
    }

    private func seekEffect(_ index: Int) -> Effect {
        .seek(to: plan.stops[index].startTime, startPlayback: true)
    }
}
