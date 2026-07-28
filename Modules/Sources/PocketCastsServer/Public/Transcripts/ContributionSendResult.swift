import Foundation

/// The outcome of a single transcript contribution / sighting upload attempt,
/// mapped from the server responses described in docs/TranscriptContributions.md §5.
///
/// The upload queue consumes this directly:
/// - `accepted` — the row is done; remove it.
/// - `retryAfter` — back off the single pending item and resume after the interval.
/// - `pauseQueue` — park the entire upload queue for the interval (the operator kill switch).
/// - `attestationRejected` — the App Attest key was rejected (401 `invalid_attestation`);
///   re-enroll per docs/AppAttest.md §1.5, then back off the owning queue.
/// - `permanentFailure` — the server rejected the payload itself (400/422); retrying the
///   identical bytes can never succeed.
public enum ContributionSendResult: Equatable, Sendable {
    case accepted
    case acceptedContribution(TranscriptContributionReceipt)
    case retryAfter(TimeInterval)
    case pauseQueue(TimeInterval)
    case attestationRejected
    case permanentFailure(String)
}

public struct TranscriptContributionReceipt: Equatable, Sendable {
    public let candidateID: String
    public let sha256: String
    public let attachmentToken: String

    public init(candidateID: String, sha256: String, attachmentToken: String) {
        self.candidateID = candidateID
        self.sha256 = sha256
        self.attachmentToken = attachmentToken
    }
}
