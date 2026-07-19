import Foundation

/// Async entry points for social discovery (Slice 10; docs/Social.md).
public extension ApiServerHandler {
    /// "Trending with friends": followees' recent listening, history-gated.
    func fetchTrendingWithFriends() async -> [TrendingPodcast]? {
        await withCheckedContinuation { continuation in
            let operation = SocialDiscoveryTask(kind: .trending)
            operation.trendingCompletion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// Podcast-page proof: named-when-visible followees + the full count.
    func fetchPodcastProof(podcastUuid: String) async -> PodcastProof? {
        await withCheckedContinuation { continuation in
            let operation = SocialDiscoveryTask(kind: .proof(podcastUuid: podcastUuid))
            operation.proofCompletion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }
}
