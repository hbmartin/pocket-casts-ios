import Foundation
import FoundationModels
import PocketCastsUtils

/// Whether the on-device language model can serve a request right now.
///
/// `reason` values are stable analytics-friendly identifiers derived from
/// `SystemLanguageModel.Availability.UnavailableReason` (plus `"unknown"` for
/// future cases), so callers can log them without importing FoundationModels.
nonisolated enum IntelligenceAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)

    /// True when the model is unavailable only because Apple Intelligence
    /// assets are still downloading (`model_not_ready`): availability can flip
    /// to `.available` without any user action, so callers that persist
    /// definitive outcomes must not treat this state as permanent.
    var isTransientlyUnavailable: Bool {
        self == .unavailable(reason: "model_not_ready")
    }
}

/// Stable error surface for on-device generation. Feature services own their
/// deterministic fallbacks, so every case is expected to be recoverable by
/// degrading to a non-AI code path.
nonisolated enum IntelligenceError: Error {
    /// The system model is not available on this device/configuration
    /// (ineligible hardware, Apple Intelligence off, assets not downloaded, Simulator).
    case modelUnavailable(reason: String)
    /// The per-call budget elapsed before the model produced a response.
    case timedOut
    /// The prompt exceeded the model's context window.
    case contextWindowExceeded
    /// The system guardrails rejected the prompt or the response, or the model refused.
    case guardrailViolation
    /// The model produced output that couldn't be decoded into the requested `Generable` type.
    case decodingFailed
    /// Any other generation failure; `description` is safe to log.
    case generationFailed(description: String)

    /// True for failures that describe this moment rather than this request:
    /// the per-call timeout, the single-generation admission gate rejecting a
    /// concurrent call, or model assets that are still downloading. Callers
    /// that persist definitive "never retry" outcomes must not cache these —
    /// an identical later attempt can succeed.
    var isTransient: Bool {
        switch self {
        case .timedOut:
            return true
        case .modelUnavailable(let reason):
            return reason == "model_not_ready"
        case .generationFailed(let description):
            return description == "concurrent_requests" || description == "rate_limited"
        case .contextWindowExceeded, .guardrailViolation, .decodingFailed:
            return false
        }
    }
}

/// Abstraction over on-device language-model generation so feature services
/// (`SummaryTakeawayGenerator`, later `HighlightTitleGenerator` /
/// `PlaylistPromptInterpreter`) stay unit-testable with mock providers.
nonisolated protocol IntelligenceProviding: Sendable {
    /// Availability is checked per call — model assets can appear (download
    /// completes) or disappear (Apple Intelligence toggled off) between calls.
    func availability() -> IntelligenceAvailability

    /// Runs one guided-generation request against the on-device model.
    /// Implementations use a short-lived session per request (no chained
    /// context between calls) and enforce a per-call timeout.
    func respond<T: Generable & Sendable>(
        instructions: String,
        prompt: String,
        generating type: T.Type
    ) async throws -> T
}

/// Thin actor wrapper around Apple's FoundationModels framework.
///
/// Design (plans/AI UX Improvements.md, cross-cutting):
/// - `SystemLanguageModel.default.availability` is checked on every call; the
///   Simulator and non-Apple-Intelligence devices degrade cleanly to
///   `IntelligenceError.modelUnavailable` so callers hit their deterministic
///   fallback layer.
/// - Each request creates a short-lived `LanguageModelSession` — no shared
///   conversation state, no cross-feature context bleed.
/// - Every call races a timeout that resumes the caller even when the
///   generation ignores cancellation (the hung call is abandoned, not
///   awaited), so a wedged model can't hold a feature's loading state. While
///   abandoned work is still running, admission stays closed so retries can't
///   accumulate more generations behind it.
/// - FoundationModels errors are mapped onto the stable `IntelligenceError`
///   surface at the boundary.
actor OnDeviceIntelligence: IntelligenceProviding {
    static let shared = OnDeviceIntelligence()

    /// Per-call budget. On-device generation normally answers in seconds; a
    /// request that runs this long has effectively hung and the feature's
    /// fallback is a better experience than a spinner.
    private let timeout: Duration
    private let watchdogReporter: @Sendable () -> Void

    /// Set before generation suspends and cleared only by that generation's
    /// work task after the underlying provider actually exits. The identifier
    /// prevents a stale completion from ever clearing newer admitted work.
    private var inFlightGenerationID: UUID?
    private var generationWatchdog: Task<Void, Never>?

    init(
        timeout: Duration = .seconds(30),
        watchdogReporter: @escaping @Sendable () -> Void = {
            FileLog.shared.addMessage("OnDeviceIntelligence: underlying generation exceeded twice its configured timeout")
        }
    ) {
        self.timeout = timeout
        self.watchdogReporter = watchdogReporter
    }

    nonisolated func availability() -> IntelligenceAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            let name: String
            switch reason {
            case .deviceNotEligible:
                name = "device_not_eligible"
            case .appleIntelligenceNotEnabled:
                name = "apple_intelligence_not_enabled"
            case .modelNotReady:
                name = "model_not_ready"
            @unknown default:
                name = "unknown"
            }
            return .unavailable(reason: name)
        }
    }

    func respond<T: Generable & Sendable>(
        instructions: String,
        prompt: String,
        generating type: T.Type
    ) async throws -> T {
        if case .unavailable(let reason) = availability() {
            throw IntelligenceError.modelUnavailable(reason: reason)
        }

        do {
            return try await performGeneration {
                let session = LanguageModelSession(model: .default, instructions: instructions)
                return try await session.respond(to: prompt, generating: T.self).content
            }
        } catch let error as IntelligenceError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.mapped(error)
        }
    }

    /// Admits at most one underlying generation at a time.
    ///
    /// Internal so tests can exercise timeout and cancellation behavior with a
    /// deterministic provider in place of `LanguageModelSession`.
    func performGeneration<T: Sendable>(
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        guard inFlightGenerationID == nil else {
            throw IntelligenceError.generationFailed(description: "concurrent_requests")
        }

        let generationID = UUID()
        inFlightGenerationID = generationID
        startGenerationWatchdog(id: generationID)
        let timeout = timeout

        return try await Self.raceAgainstTimeout(timeout: timeout) { [weak self] in
            do {
                // Avoid starting provider work if cancellation wins before this
                // unstructured task gets its first turn.
                try Task.checkCancellation()
                let result = try await work()
                await self?.generationDidFinish(id: generationID)
                return result
            } catch {
                await self?.generationDidFinish(id: generationID)
                throw error
            }
        }
    }

    private func generationDidFinish(id: UUID) {
        guard inFlightGenerationID == id else { return }
        generationWatchdog?.cancel()
        generationWatchdog = nil
        inFlightGenerationID = nil
    }

    /// The caller-facing timeout deliberately abandons non-cooperative work.
    /// Keep observing that work so a provider hang is visible in diagnostics,
    /// and retain the completed watchdog until the generation itself exits.
    private func startGenerationWatchdog(id: UUID) {
        let threshold = timeout + timeout
        generationWatchdog = Task { [weak self] in
            do {
                try await Task.sleep(for: threshold)
            } catch {
                return
            }
            await self?.reportGenerationWatchdogIfNeeded(id: id)
        }
    }

    private func reportGenerationWatchdogIfNeeded(id: UUID) {
        guard inFlightGenerationID == id else { return }
        watchdogReporter()
        inFlightGenerationID = nil
        generationWatchdog = nil
    }

    /// Races `work` against the timeout without awaiting a hung child on the
    /// way out: a task-group race implicitly awaits its cancelled children
    /// before returning, so a generation call that ignores cancellation would
    /// still wedge the caller past the deadline. Here the loser is cancelled
    /// and abandoned — a truly non-cooperative generation keeps running in the
    /// background, but the caller gets its timeout on time.
    /// Internal (not private) so the timeout/cancellation contract is unit-testable
    /// with stubbed work in place of a real `LanguageModelSession`.
    nonisolated static func raceAgainstTimeout<T: Sendable>(
        timeout: Duration,
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        // A stream continuation is Sendable and finish-once by design, so the
        // two racers can both try to settle it without a hand-rolled guard.
        let (stream, continuation) = AsyncThrowingStream<T, Error>.makeStream()

        let workTask = Task {
            do {
                continuation.yield(try await work())
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        let timerTask = Task {
            do {
                try await Task.sleep(for: timeout)
                continuation.finish(throwing: IntelligenceError.timedOut)
            } catch is CancellationError {
                // The work completed or the caller was cancelled. Do not let a
                // cancelled timer overwrite that outcome with a timeout.
            } catch {
                continuation.finish(throwing: error)
            }
        }
        defer {
            // No-ops for the finished winner; the timed-out (or abandoned)
            // generation gets its cancellation signal here.
            workTask.cancel()
            timerTask.cancel()
        }

        guard let first = try await stream.first(where: { _ in true }) else {
            // The stream ended without a value: either the caller was
            // cancelled (iteration stops on task cancellation) or the timer won.
            if Task.isCancelled { throw CancellationError() }
            throw IntelligenceError.timedOut
        }
        return first
    }

    /// Maps FoundationModels generation errors onto the stable `IntelligenceError` surface.
    nonisolated private static func mapped(_ error: any Error) -> IntelligenceError {
        guard let generationError = error as? LanguageModelSession.GenerationError else {
            return .generationFailed(description: String(describing: type(of: error)))
        }
        switch generationError {
        case .exceededContextWindowSize:
            return .contextWindowExceeded
        case .guardrailViolation, .refusal:
            return .guardrailViolation
        case .decodingFailure:
            return .decodingFailed
        case .assetsUnavailable:
            return .modelUnavailable(reason: "assets_unavailable")
        case .rateLimited:
            return .generationFailed(description: "rate_limited")
        case .concurrentRequests:
            return .generationFailed(description: "concurrent_requests")
        case .unsupportedGuide:
            return .generationFailed(description: "unsupported_guide")
        case .unsupportedLanguageOrLocale:
            return .generationFailed(description: "unsupported_language_or_locale")
        @unknown default:
            return .generationFailed(description: "unknown_generation_error")
        }
    }
}
