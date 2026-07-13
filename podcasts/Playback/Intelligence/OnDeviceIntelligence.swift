import Foundation
import FoundationModels

/// Whether the on-device language model can serve a request right now.
///
/// `reason` values are stable analytics-friendly identifiers derived from
/// `SystemLanguageModel.Availability.UnavailableReason` (plus `"unknown"` for
/// future cases), so callers can log them without importing FoundationModels.
nonisolated enum IntelligenceAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)
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
/// - Every call races a timeout so a hung generation can never wedge a
///   feature's loading state.
/// - FoundationModels errors are mapped onto the stable `IntelligenceError`
///   surface at the boundary.
actor OnDeviceIntelligence: IntelligenceProviding {
    static let shared = OnDeviceIntelligence()

    /// Per-call budget. On-device generation normally answers in seconds; a
    /// request that runs this long has effectively hung and the feature's
    /// fallback is a better experience than a spinner.
    private let timeout: Duration

    init(timeout: Duration = .seconds(30)) {
        self.timeout = timeout
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

        let session = LanguageModelSession(model: .default, instructions: instructions)
        let timeout = timeout
        do {
            return try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask {
                    try await session.respond(to: prompt, generating: T.self).content
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw IntelligenceError.timedOut
                }
                guard let first = try await group.next() else {
                    throw IntelligenceError.timedOut
                }
                group.cancelAll()
                return first
            }
        } catch let error as IntelligenceError {
            throw error
        } catch {
            throw Self.mapped(error)
        }
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
