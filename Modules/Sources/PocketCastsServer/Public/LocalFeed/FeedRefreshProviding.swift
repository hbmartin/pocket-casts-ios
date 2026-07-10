import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// The strategy seam for feed refresh: produces a `PodcastRefreshResponse` for the given
/// podcasts, however the episodes are actually sourced (Pocket Casts refresh servers,
/// on-device feed parsing, or both). Everything downstream of `RefreshManager` —
/// `RefreshOperation`, sync, notifications — consumes only the response, so swapping the
/// producer requires no other changes.
public protocol FeedRefreshProviding: Sendable {
    func refresh(podcasts: [Podcast], completion: @escaping @Sendable (PodcastRefreshResponse?) -> Void)
}

/// The historical behavior: everything refreshes via `MainServerHandler`.
public struct ServerFeedRefreshProvider: FeedRefreshProviding {
    public init() {}

    public func refresh(podcasts: [Podcast], completion: @escaping @Sendable (PodcastRefreshResponse?) -> Void) {
        MainServerHandler.shared.refresh(podcasts: podcasts, completion: completion)
    }
}

/// Partitions podcasts by their per-podcast `refreshSource`, fans out to the server and
/// local providers, and merges the two `podcastUpdates` maps into a single response. The
/// two identity spaces stay apart because each podcast is owned by exactly one regime.
public struct CompositeFeedRefreshProvider: FeedRefreshProviding {
    private let serverProvider: FeedRefreshProviding
    private let localProvider: FeedRefreshProviding

    public init(serverProvider: FeedRefreshProviding = ServerFeedRefreshProvider(),
                localProvider: FeedRefreshProviding = LocalFeedRefreshProvider()) {
        self.serverProvider = serverProvider
        self.localProvider = localProvider
    }

    public func refresh(podcasts: [Podcast], completion: @escaping @Sendable (PodcastRefreshResponse?) -> Void) {
        let localPodcasts = podcasts.filter { $0.isLocalFeedSourced }
        let serverPodcasts = podcasts.filter { !$0.isLocalFeedSourced }

        // Single-regime libraries take the direct path: an account-only user sees exactly
        // the historical server behavior.
        if localPodcasts.isEmpty {
            serverProvider.refresh(podcasts: serverPodcasts, completion: completion)
            return
        }
        if serverPodcasts.isEmpty {
            localProvider.refresh(podcasts: localPodcasts, completion: completion)
            return
        }

        let collector = ResponseCollector()
        let group = DispatchGroup()

        group.enter()
        serverProvider.refresh(podcasts: serverPodcasts) { response in
            collector.add(response)
            group.leave()
        }

        group.enter()
        localProvider.refresh(podcasts: localPodcasts) { response in
            collector.add(response)
            group.leave()
        }

        group.notify(queue: .global()) {
            completion(Self.merged(collector.responses))
        }
    }

    /// Succeeds if either regime succeeded (the other's failure is already logged);
    /// fails only when both did, so one unreachable side can't wipe out the other's
    /// new episodes.
    static func merged(_ responses: [PodcastRefreshResponse?]) -> PodcastRefreshResponse {
        let successes = responses.compactMap { $0 }.filter { $0.success() }
        guard !successes.isEmpty else { return PodcastRefreshResponse.failedResponse() }

        // Keys are podcast uuids and each podcast is owned by exactly one provider, so
        // the maps are disjoint; keep the first value defensively if they ever collide.
        var mergedUpdates = [String: [RefreshEpisode]]()
        for success in successes {
            mergedUpdates.merge(success.result?.podcastUpdates ?? [:]) { current, _ in current }
        }

        var merged = PodcastRefreshResponse()
        merged.status = "ok"
        merged.result = RefreshResult(podcastUpdates: mergedUpdates)
        return merged
    }

    private final class ResponseCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var collected = [PodcastRefreshResponse?]()

        var responses: [PodcastRefreshResponse?] {
            lock.lock()
            defer { lock.unlock() }
            return collected
        }

        func add(_ response: PodcastRefreshResponse?) {
            lock.lock()
            defer { lock.unlock() }
            collected.append(response)
        }
    }
}
