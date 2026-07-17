import Foundation

/// Async entry points for the follow graph + activity feed (Slice 5;
/// docs/Social.md, ADR-0009). Ships behind FeatureFlag.socialProfiles.
public extension ApiServerHandler {
    /// Follows a handle; returns .active (open) or .pending (approval-gated),
    /// nil on failure (unknown/blocked handles read identically as failure).
    func follow(handle: String) async -> FollowState? {
        await withCheckedContinuation { continuation in
            let operation = FollowTask(handle: handle, unfollow: false)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// Unfollows (or cancels a pending request). Returns .none on success.
    func unfollow(handle: String) async -> FollowState? {
        await withCheckedContinuation { continuation in
            let operation = FollowTask(handle: handle, unfollow: true)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    func fetchFollowers(limit: Int = 100, offset: Int = 0) async -> FollowList? {
        await fetchFollowList(kind: .followers, limit: limit, offset: offset)
    }

    func fetchFollowing(limit: Int = 100, offset: Int = 0) async -> FollowList? {
        await fetchFollowList(kind: .following, limit: limit, offset: offset)
    }

    /// Pending follow requests awaiting the caller's approval.
    func fetchFollowRequests(limit: Int = 100, offset: Int = 0) async -> FollowList? {
        await fetchFollowList(kind: .requests, limit: limit, offset: offset)
    }

    private func fetchFollowList(kind: FollowListTask.Kind, limit: Int, offset: Int) async -> FollowList? {
        await withCheckedContinuation { continuation in
            let operation = FollowListTask(kind: kind, limit: Int32(limit), offset: Int32(offset))
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// Accepts or declines a pending follow request.
    func respondToFollowRequest(requesterHandle: String, accept: Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            let operation = FollowApproveTask(requesterHandle: requesterHandle, accept: accept)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// The caller's activity feed, newest first; page with beforeUnixMs.
    func fetchFeed(limit: Int = 50, beforeUnixMs: Int64 = 0) async -> [FeedItem]? {
        await withCheckedContinuation { continuation in
            let operation = SocialFeedTask(limit: Int32(limit), beforeUnixMs: beforeUnixMs)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }
}
