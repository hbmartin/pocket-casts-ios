import Combine
import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Pushes new and edited highlights to Readwise (Highlights program S6).
///
/// Fire-and-forget with a durable pending set: bookmark events enqueue uuids
/// into UserDefaults, a debounced drain batches them into one API call, and
/// failures re-enqueue with exponential backoff. `highlight_url` carries the
/// bookmark uuid so re-pushes update in place rather than duplicate.
@MainActor
final class ReadwiseSyncManager {
    static let shared = ReadwiseSyncManager()

    private static let pendingKey = "readwise.pendingUuids"
    private static let authFailedKey = "readwise.authFailed"
    private static let debounceInterval: TimeInterval = 5
    private static let maxBackoff: TimeInterval = 30 * 60

    private var cancellables = Set<AnyCancellable>()
    private var drainTask: Task<Void, Never>?
    private var backoff: TimeInterval = 0

    private let bookmarkManager: BookmarkManager
    private let client: ReadwiseClient

    init(bookmarkManager: BookmarkManager = PlaybackManager.shared.bookmarkManager,
         client: ReadwiseClient = ReadwiseClient()) {
        self.bookmarkManager = bookmarkManager
        self.client = client
    }

    var isEnabled: Bool { ReadwiseKeyStore.token() != nil }

    /// True after the server rejected the stored token (revoked or rotated on
    /// readwise.io). Pushes stay paused — retrying a dead token on every
    /// capture would just grow the queue — until a fresh token is saved, and
    /// the settings screen shows the reconnect state instead of "Connected".
    /// Published (stored, mirrored to UserDefaults) so an already-open
    /// settings screen sees a mid-session revocation instead of a stale
    /// "Connected".
    @Published private(set) var needsReauthorization = UserDefaults.standard.bool(forKey: ReadwiseSyncManager.authFailedKey) {
        didSet { UserDefaults.standard.set(needsReauthorization, forKey: Self.authFailedKey) }
    }

    /// Idempotent; called at app start (flag-gated) and after a token is saved.
    func startObservingIfNeeded() {
        guard FeatureFlag.readwiseSync.enabled, isEnabled, cancellables.isEmpty else { return }

        bookmarkManager.onBookmarkCreated
            .receive(on: DispatchQueue.main)
            .filter { !$0.isDuplicate }
            .sink { [weak self] event in self?.enqueue(uuid: event.uuid) }
            .store(in: &cancellables)

        bookmarkManager.onBookmarkChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in self?.enqueue(uuid: event.uuid) }
            .store(in: &cancellables)

        // Anything left over from a previous run.
        if !pendingUuids.isEmpty {
            scheduleDrain(after: Self.debounceInterval)
        }
    }

    /// Saves the token (nil disables) and validates it against the API.
    /// Returns true when the token is accepted.
    func updateToken(_ token: String?) async -> Bool {
        guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            guard ReadwiseKeyStore.setToken(nil) else {
                FileLog.shared.addMessage("[Readwise] failed to remove token from Keychain")
                return false
            }
            needsReauthorization = false
            cancellables.removeAll()
            drainTask?.cancel()
            Analytics.track(.readwiseDisabled)
            return true
        }

        do {
            try await client.validateToken(token)
        } catch {
            return false
        }

        guard ReadwiseKeyStore.setToken(token) else {
            FileLog.shared.addMessage("[Readwise] failed to save token to Keychain")
            return false
        }
        needsReauthorization = false
        startObservingIfNeeded()
        pushAll()
        Analytics.track(.readwiseEnabled)
        return true
    }

    /// Queues every highlight-worthy bookmark (initial backfill after
    /// enabling) — the same acceptance rule `resolveHighlight` applies, so the
    /// backfill corpus matches what steady-state edits would sync.
    func pushAll() {
        guard FeatureFlag.readwiseSync.enabled, isEnabled else { return }
        for bookmark in bookmarkManager.allBookmarks()
        where bookmark.excerpt != nil || bookmark.title != L10n.bookmarkDefaultTitle {
            enqueue(uuid: bookmark.uuid)
        }
    }

    // MARK: - Queue

    private var pendingUuids: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.pendingKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Self.pendingKey) }
    }

    private func enqueue(uuid: String) {
        guard isEnabled else { return }
        var pending = pendingUuids
        if !pending.contains(uuid) {
            pending.append(uuid)
            pendingUuids = pending
        }
        // The backlog stays durable while auth is broken; re-connecting drains it.
        guard !needsReauthorization else { return }
        scheduleDrain(after: max(Self.debounceInterval, backoff))
    }

    private func scheduleDrain(after delay: TimeInterval) {
        drainTask?.cancel()
        drainTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.drain()
        }
    }

    private func drain() async {
        guard !needsReauthorization, let token = ReadwiseKeyStore.token() else { return }

        let uuids = pendingUuids
        guard !uuids.isEmpty else { return }

        let highlights = uuids.compactMap { resolveHighlight(uuid: $0) }
        guard !highlights.isEmpty else {
            pendingUuids = []
            return
        }

        do {
            try await client.push(highlights, token: token)
            // Only clear what we sent; captures during the request stay queued.
            pendingUuids = pendingUuids.filter { !uuids.contains($0) }
            backoff = 0
            Analytics.track(.readwisePushed, properties: ["count": highlights.count])
        } catch ReadwiseClient.ClientError.rateLimited(let retryAfter) {
            // Raise backoff too: `enqueue` reschedules at max(debounce, backoff),
            // so without this a capture during the wait would cancel the
            // Retry-After timer and re-hit the rate-limited API in 5s.
            backoff = min(max(retryAfter, Self.debounceInterval), Self.maxBackoff)
            scheduleDrain(after: backoff)
        } catch ReadwiseClient.ClientError.unauthorized {
            // Token revoked server-side: pause pushes durably and surface the
            // reconnect state in Settings; the queue survives for the re-auth.
            needsReauthorization = true
            FileLog.shared.addMessage("[Readwise] token rejected; pausing pushes until a new token is saved")
        } catch {
            backoff = min(max(Self.debounceInterval, backoff * 2), Self.maxBackoff)
            FileLog.shared.addMessage("[Readwise] push failed (retry in \(Int(backoff))s): \(error)")
            scheduleDrain(after: backoff)
        }
    }

    private func resolveHighlight(uuid: String) -> ReadwiseClient.Highlight? {
        guard let bookmark = bookmarkManager.bookmark(for: uuid),
              bookmark.excerpt != nil || bookmark.title != L10n.bookmarkDefaultTitle else {
            return nil
        }
        let episode = bookmarkManager.episode(for: bookmark)
        let podcastTitle = (episode as? Episode).flatMap {
            DataManager.sharedManager.findPodcast(uuid: $0.podcastUuid)?.title
        }
        let shareLink = (episode as? Episode).map { "\($0.shareURL)?t=\(Int(bookmark.time.rounded()))" }

        return ReadwiseClient.highlight(
            excerpt: bookmark.excerpt,
            bookmarkTitle: bookmark.title,
            bookmarkUuid: bookmark.uuid,
            time: bookmark.time,
            created: bookmark.created,
            tags: bookmark.tags,
            episodeTitle: episode?.displayableTitle() ?? "",
            podcastTitle: podcastTitle,
            shareLink: shareLink
        )
    }
}
