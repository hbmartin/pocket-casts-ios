import Foundation

/// Async entry points for the social moderation + safety surface
/// (docs/SocialModeration.md, ADR-0007). Ships dark behind
/// FeatureFlag.socialProfiles.
public extension ApiServerHandler {
    /// Blocks or unblocks a user (mutual invisibility while blocked). Returns
    /// whether the server acknowledged.
    func setBlocked(_ blocked: Bool, targetUserId: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let operation = SocialBlockTask(targetUserId: targetUserId, block: blocked)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// Mutes or unmutes a user (one-way hide; the muted party is not notified).
    func setMuted(_ muted: Bool, targetUserId: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let operation = SocialMuteTask(targetUserId: targetUserId, mute: muted)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// Reports a user into the moderation triage queue.
    func reportUser(targetUserId: String,
                    reason: SocialReportReason,
                    context: String = "",
                    targetType: String = "",
                    contentRef: String = "") async -> Bool {
        await withCheckedContinuation { continuation in
            let operation = SocialReportTask(targetUserId: targetUserId,
                                             reason: reason,
                                             context: context,
                                             targetType: targetType,
                                             contentRef: contentRef)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// GDPR erasure of the caller's social profile (clears PII, tombstones the
    /// handle). Wired into the account-deletion path.
    func eraseSocialProfile() async -> Bool {
        await withCheckedContinuation { continuation in
            let operation = SocialEraseTask()
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }
}
