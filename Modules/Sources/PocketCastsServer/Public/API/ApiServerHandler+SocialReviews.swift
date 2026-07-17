import Foundation

/// Async entry points for written reviews + episode reactions (Slice 3;
/// docs/Social.md). Ships behind FeatureFlag.socialProfiles.
public extension ApiServerHandler {
    /// Upserts the caller's attributed review text (join-required server-side).
    func submitReview(podcastUuid: String, text: String) async -> PodcastReview? {
        await withCheckedContinuation { continuation in
            let operation = ReviewSubmitTask(podcastUuid: podcastUuid, text: text)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// Deletes the caller's review text for a podcast. Idempotent.
    func deleteReview(podcastUuid: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let operation = ReviewDeleteTask(podcastUuid: podcastUuid)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// The public review page for a podcast (blocked authors already filtered
    /// server-side; includes your_review when signed in).
    func fetchReviews(podcastUuid: String, limit: Int = 50, offset: Int = 0) async -> PodcastReviewPage? {
        await withCheckedContinuation { continuation in
            let operation = ReviewListTask(podcastUuid: podcastUuid, limit: Int32(limit), offset: Int32(offset))
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// Sets (or clears, when nil) the caller's single reaction on an episode.
    func setReaction(episodeUuid: String, kind: ReactionKind?) async -> Bool {
        await withCheckedContinuation { continuation in
            let operation = ReactionSetTask(episodeUuid: episodeUuid, kind: kind)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// Aggregate reaction counts for an episode plus the caller's own.
    func fetchReactions(episodeUuid: String) async -> EpisodeReactions? {
        await withCheckedContinuation { continuation in
            let operation = ReactionListTask(episodeUuid: episodeUuid)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }
}
