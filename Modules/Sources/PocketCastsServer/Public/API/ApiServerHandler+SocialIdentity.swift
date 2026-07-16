import Foundation

/// Async entry points for the social identity surface (docs/Social.md). Mirrors
/// the ApiServerHandler+UserPodcastRating shape: wrap each *Task in a checked
/// continuation on `apiQueue`. Ships dark behind FeatureFlag.socialProfiles.
public extension ApiServerHandler {
    /// Checks whether a handle can be claimed. Returns the server verdict plus
    /// the normalized handle form the UI should display.
    func checkHandleAvailability(_ handle: String) async -> (status: SocialHandleAvailability, normalizedHandle: String) {
        await withCheckedContinuation { continuation in
            let operation = HandleAvailabilityTask(handle: handle)
            operation.completion = { status, normalized in
                continuation.resume(returning: (status, normalized))
            }
            apiQueue.addOperation(operation)
        }
    }

    /// Claims the handle and creates the profile (all fields private except the
    /// display name). Returns the created profile, or nil on failure.
    func joinSocial(handle: String, displayName: String, termsVersion: Int) async -> SocialProfile? {
        await withCheckedContinuation { continuation in
            let operation = SocialJoinTask(handle: handle, displayName: displayName, termsVersion: Int32(termsVersion))
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// Fetches the caller's own profile (all fields + all visibility tiers).
    func getSocialProfile() async -> SocialProfile? {
        await withCheckedContinuation { continuation in
            let operation = SocialProfileGetTask()
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// Updates the caller's editable profile fields + per-field visibility. The
    /// handle is immutable and is never sent. Returns the updated profile.
    func updateSocialProfile(_ profile: SocialProfile) async -> SocialProfile? {
        await withCheckedContinuation { continuation in
            let operation = SocialProfileUpdateTask(profile: profile)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// Fetches another user's public profile by handle. The server has already
    /// applied per-field visibility and the viewer's block relationship; a
    /// blocked/missing/tombstoned handle returns nil.
    func fetchPublicProfile(handle: String) async -> SocialPublicProfile? {
        await withCheckedContinuation { continuation in
            let operation = PublicProfileTask(handle: handle)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }
}
