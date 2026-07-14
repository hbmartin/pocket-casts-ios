import Combine
import CoreSpotlight
import Foundation
import PocketCastsDataModel
import PocketCastsUtils
import Synchronization

/// The slice of `CSSearchableIndex` the coordinator uses, injectable for tests.
/// The async requirements are `nonisolated(nonsending)` (run on the caller's
/// executor) so non-Sendable `CSSearchableItem`s never cross an isolation
/// boundary — required for conformances in targets without
/// `NonisolatedNonsendingByDefault`.
nonisolated protocol SearchableIndexing: Sendable {
    func isAvailable() -> Bool
    nonisolated(nonsending) func index(_ items: [CSSearchableItem]) async throws
    nonisolated(nonsending) func deleteItems(identifiers: [String]) async throws
    nonisolated(nonsending) func deleteAll(domainIdentifiers: [String]) async throws
}

nonisolated struct LiveSearchableIndex: SearchableIndexing {
    func isAvailable() -> Bool {
        CSSearchableIndex.isIndexingAvailable()
    }

    func index(_ items: [CSSearchableItem]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            CSSearchableIndex.default().indexSearchableItems(items) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    func deleteItems(identifiers: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: identifiers) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    func deleteAll(domainIdentifiers: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: domainIdentifiers) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
}

/// Mirrors downloaded episodes into iOS Spotlight as `CSSearchableItem`s.
///
/// Modeled on `TranscriptAcquisitionCoordinator`: a process-lifetime singleton
/// created from `AppDelegate`, observing typed episode messages, with feature
/// gates checked per event so Beta-menu toggles apply without a relaunch.
/// Writes are tracked in a persisted identifier set (Application Support) so a
/// daily reconciliation can diff expected-vs-written — catching bulk changes,
/// failed batches, and flag flips — and only ever deletes identifiers this app
/// itself wrote.
nonisolated final class SpotlightIndexCoordinator: Sendable {
    static let shared = SpotlightIndexCoordinator()

    /// Bump to force a full rebuild after an item-format change.
    static let schemaVersion = 1
    static let reconcileInterval: TimeInterval = 24 * 3600
    static let indexBatchSize = 100

    enum DefaultsKey {
        static let lastReconcile = "SpotlightIndexLastReconcile"
        static let schemaVersion = "SpotlightIndexSchemaVersion"
    }

    private struct PendingChanges {
        var uuids: Set<String> = []
        var bookmarkUuids: Set<String> = []
        var needsFullRefresh = false
        var flushScheduled = false
    }

    private let index: any SearchableIndexing
    /// UserDefaults is documented thread-safe; it just predates Sendable.
    nonisolated(unsafe) private let defaults: UserDefaults
    private let stateFileURL: URL
    private let debounceSeconds: TimeInterval
    private let isEnabled: @Sendable () -> Bool
    /// Metadata for an episode that should be indexed; nil means the identifier
    /// should be deleted (episode gone, not downloaded, or a user file).
    private let resolveEpisode: @Sendable (String) -> SpotlightItemBuilder.EpisodeMetadata?
    private let downloadedEpisodes: @Sendable () -> [SpotlightItemBuilder.EpisodeMetadata]
    /// Byte-capped transcript text for an indexed episode (nil = none indexed).
    private let transcriptText: @Sendable (String) -> String?
    /// Metadata for a Highlight that should be indexed; nil means delete
    /// (bookmark gone, or not enriched with an excerpt).
    private let resolveHighlight: @Sendable (String) -> SpotlightItemBuilder.HighlightMetadata?
    private let allHighlights: @Sendable () -> [SpotlightItemBuilder.HighlightMetadata]

    /// Held for the coordinator's whole (process-long) lifetime; set once in start().
    private let observationTokens = Mutex<[NotificationCenter.ObservationToken]>([])
    /// AnyCancellable isn't Sendable; main-actor isolation guards it instead
    /// (subscriptions are only ever created there, once).
    @MainActor private var bookmarkSubscriptions = Set<AnyCancellable>()
    private let pending = Mutex<PendingChanges>(PendingChanges())
    private let persistedIdentifiers = Mutex<Set<String>?>(nil)

    init(index: any SearchableIndexing = LiveSearchableIndex(),
         defaults: UserDefaults = .standard,
         stateFileURL: URL = SpotlightIndexCoordinator.defaultStateFileURL,
         debounceSeconds: TimeInterval = 2,
         isEnabled: @escaping @Sendable () -> Bool = { FeatureFlag.spotlightIndexing.enabled },
         resolveEpisode: @escaping @Sendable (String) -> SpotlightItemBuilder.EpisodeMetadata? = SpotlightIndexCoordinator.liveResolveEpisode,
         downloadedEpisodes: @escaping @Sendable () -> [SpotlightItemBuilder.EpisodeMetadata] = SpotlightIndexCoordinator.liveDownloadedEpisodes,
         transcriptText: @escaping @Sendable (String) -> String? = SpotlightIndexCoordinator.liveTranscriptText,
         resolveHighlight: @escaping @Sendable (String) -> SpotlightItemBuilder.HighlightMetadata? = SpotlightIndexCoordinator.liveResolveHighlight,
         allHighlights: @escaping @Sendable () -> [SpotlightItemBuilder.HighlightMetadata] = SpotlightIndexCoordinator.liveAllHighlights) {
        self.index = index
        self.defaults = defaults
        self.stateFileURL = stateFileURL
        self.debounceSeconds = debounceSeconds
        self.isEnabled = isEnabled
        self.resolveEpisode = resolveEpisode
        self.downloadedEpisodes = downloadedEpisodes
        self.transcriptText = transcriptText
        self.resolveHighlight = resolveHighlight
        self.allHighlights = allHighlights
    }

    /// Begins observing episode lifecycle and transcript-index messages. Call
    /// once at launch.
    func start() {
        let downloadToken = NotificationCenter.default.addObserver(for: EpisodeDownloaded.self) { [weak self] message in
            self?.episodeChanged(uuid: message.uuid)
        }
        let statusToken = NotificationCenter.default.addObserver(for: EpisodeDownloadStatusChanged.self) { [weak self] message in
            // A nil uuid is a bulk change (mark-all, cleanup): re-derive everything.
            self?.episodeChanged(uuid: message.uuid)
        }
        let transcriptToken = NotificationCenter.default.addObserver(for: TranscriptIndexUpdated.self) { [weak self] message in
            // Re-index so the episode item picks up the transcript textContent.
            self?.episodeChanged(uuid: message.uuid)
        }
        observationTokens.withLock { $0 = [downloadToken, statusToken, transcriptToken] }
    }

    /// Mirrors Highlight lifecycle (bookmarks gaining excerpts, deletions) into
    /// the index. Separate from `start()` because the bookmark manager lives on
    /// the main actor.
    @MainActor
    func startBookmarkObservations(bookmarkManager: BookmarkManager) {
        bookmarkManager.onBookmarkChanged
            .sink { [weak self] event in
                // Only enrichment makes a bookmark a Highlight; title edits on
                // an already-indexed one also refresh via the same path.
                self?.highlightChanged(bookmarkUuid: event.uuid)
            }
            .store(in: &bookmarkSubscriptions)
        bookmarkManager.onBookmarksDeleted
            .sink { [weak self] event in
                event.items.forEach { self?.highlightChanged(bookmarkUuid: $0.uuid) }
            }
            .store(in: &bookmarkSubscriptions)
    }

    // MARK: - Event intake (debounced)

    func episodeChanged(uuid: String?) {
        enqueueChange { state in
            if let uuid {
                state.uuids.insert(uuid)
            } else {
                state.needsFullRefresh = true
            }
        }
    }

    func highlightChanged(bookmarkUuid: String) {
        enqueueChange { state in
            state.bookmarkUuids.insert(bookmarkUuid)
        }
    }

    private func enqueueChange(_ apply: (inout PendingChanges) -> Void) {
        let shouldSchedule: Bool = pending.withLock { state in
            apply(&state)
            guard !state.flushScheduled else { return false }
            state.flushScheduled = true
            return true
        }
        guard shouldSchedule else { return }

        Task(priority: .utility) { [weak self, debounceSeconds] in
            try? await Task.sleep(for: .seconds(debounceSeconds))
            await self?.flushPending()
        }
    }

    /// Applies the coalesced changes. Exposed for tests (which call it directly
    /// after seeding events with a long debounce).
    func flushPending() async {
        let (uuids, bookmarkUuids, fullRefresh): (Set<String>, Set<String>, Bool) = pending.withLock { state in
            defer { state = PendingChanges() }
            return (state.uuids, state.bookmarkUuids, state.needsFullRefresh)
        }
        guard isEnabled(), index.isAvailable() else { return }

        if fullRefresh {
            await rebuildAll()
            return
        }
        guard !uuids.isEmpty || !bookmarkUuids.isEmpty else { return }

        var itemsToIndex: [CSSearchableItem] = []
        var identifiersToDelete: [String] = []
        for uuid in uuids.sorted() {
            if let metadata = resolveEpisode(uuid) {
                itemsToIndex.append(SpotlightItemBuilder.episodeItem(metadata, transcriptText: transcriptText(uuid)))
            } else {
                identifiersToDelete.append(SpotlightItemBuilder.identifier(for: .episode(uuid: uuid)))
            }
        }
        for bookmarkUuid in bookmarkUuids.sorted() {
            if let metadata = resolveHighlight(bookmarkUuid) {
                itemsToIndex.append(SpotlightItemBuilder.highlightItem(metadata))
            } else {
                identifiersToDelete.append(SpotlightItemBuilder.identifier(for: .highlight(bookmarkUuid: bookmarkUuid)))
            }
        }

        do {
            if !identifiersToDelete.isEmpty {
                try await index.deleteItems(identifiers: identifiersToDelete)
                mutatePersisted { $0.subtract(identifiersToDelete) }
            }
            if !itemsToIndex.isEmpty {
                try await index.index(itemsToIndex)
                mutatePersisted { $0.formUnion(itemsToIndex.map(\.uniqueIdentifier)) }
            }
        } catch {
            // State only records confirmed writes; the next reconciliation retries.
            FileLog.shared.addMessage("[Spotlight] incremental update failed: \(error)")
        }
    }

    // MARK: - Reconciliation

    /// Launch-time reconciliation, throttled to once per `reconcileInterval`.
    /// With the feature off (or indexing unavailable) it instead clears anything
    /// this app previously wrote — once — so a flag flip cleans up after itself.
    func reconcileIfDue() async {
        guard isEnabled(), index.isAvailable() else {
            await clearEverythingOnce()
            return
        }

        let last = defaults.double(forKey: DefaultsKey.lastReconcile)
        let schema = defaults.integer(forKey: DefaultsKey.schemaVersion)
        let due = schema != Self.schemaVersion
            || Date().timeIntervalSince1970 - last >= Self.reconcileInterval
        guard due else { return }

        await rebuildAll()
    }

    /// Recomputes the full expected set (episodes and Highlights) and rewrites
    /// Spotlight to match. Also the "Rebuild Spotlight Index" settings action.
    func rebuildAll() async {
        guard isEnabled(), index.isAvailable() else { return }

        let episodeItems = downloadedEpisodes().map { SpotlightItemBuilder.episodeItem($0, transcriptText: transcriptText($0.uuid)) }
        let highlightItems = allHighlights().map { SpotlightItemBuilder.highlightItem($0) }
        let items = episodeItems + highlightItems
        let expected = Set(items.map(\.uniqueIdentifier))
        let plan = SpotlightReconciliationPlan.make(expected: expected, persisted: loadPersisted())

        do {
            if !plan.toDelete.isEmpty {
                try await index.deleteItems(identifiers: plan.toDelete)
            }
            for chunk in items.chunked(size: Self.indexBatchSize) {
                try await index.index(chunk)
            }
            savePersisted(expected)
            defaults.set(Date().timeIntervalSince1970, forKey: DefaultsKey.lastReconcile)
            defaults.set(Self.schemaVersion, forKey: DefaultsKey.schemaVersion)
            FileLog.shared.addMessage("[Spotlight] reconciled: \(items.count) indexed, \(plan.toDelete.count) deleted")
            Analytics.track(.spotlightReconcileCompleted, properties: [
                "indexed": items.count,
                "deleted": plan.toDelete.count
            ])
        } catch {
            FileLog.shared.addMessage("[Spotlight] reconcile failed: \(error)")
        }
    }

    private func clearEverythingOnce() async {
        guard !loadPersisted().isEmpty else { return }
        do {
            try await index.deleteAll(domainIdentifiers: [SpotlightItemBuilder.episodeDomain, SpotlightItemBuilder.highlightDomain])
            savePersisted([])
            FileLog.shared.addMessage("[Spotlight] cleared index (feature disabled)")
        } catch {
            FileLog.shared.addMessage("[Spotlight] clear failed: \(error)")
        }
    }

    // MARK: - Persisted identifier state

    static var defaultStateFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("spotlight-index-state.json")
    }

    private func loadPersisted() -> Set<String> {
        persistedIdentifiers.withLock { cached in
            if let cached { return cached }
            let loaded: Set<String>
            if let data = try? Data(contentsOf: stateFileURL),
               let identifiers = try? JSONDecoder().decode(Set<String>.self, from: data) {
                loaded = identifiers
            } else {
                loaded = []
            }
            cached = loaded
            return loaded
        }
    }

    private func mutatePersisted(_ mutate: (inout Set<String>) -> Void) {
        var current = loadPersisted()
        mutate(&current)
        savePersisted(current)
    }

    private func savePersisted(_ identifiers: Set<String>) {
        persistedIdentifiers.withLock { $0 = identifiers }
        do {
            let data = try JSONEncoder().encode(identifiers)
            try data.write(to: stateFileURL, options: .atomic)
        } catch {
            FileLog.shared.addMessage("[Spotlight] failed to persist index state: \(error)")
        }
    }

    // MARK: - Live lookups

    /// Only real, currently downloaded `Episode`s qualify; user (uploaded) files
    /// never do — they have no podcast metadata and stay device-private.
    private static let liveResolveEpisode: @Sendable (String) -> SpotlightItemBuilder.EpisodeMetadata? = { uuid in
        guard let episode = DataManager.sharedManager.findEpisode(uuid: uuid),
              episode.episodeStatus == DownloadStatus.downloaded.rawValue else {
            return nil
        }
        return metadata(for: episode)
    }

    private static let liveDownloadedEpisodes: @Sendable () -> [SpotlightItemBuilder.EpisodeMetadata] = {
        DataManager.sharedManager.findDownloadedEpisodes()
            .compactMap { $0 as? Episode }
            .map { metadata(for: $0) }
    }

    private static func metadata(for episode: Episode) -> SpotlightItemBuilder.EpisodeMetadata {
        SpotlightItemBuilder.EpisodeMetadata(
            uuid: episode.uuid,
            title: episode.title ?? "",
            podcastTitle: DataManager.sharedManager.findPodcast(uuid: episode.podcastUuid, includeUnsubscribed: true)?.title,
            episodeDescription: episode.episodeDescription,
            publishedDate: episode.publishedDate,
            duration: episode.duration
        )
    }

    /// Byte-capped transcript text for the episode, preferring the generated
    /// corpus (native audio timeline, always kept) over the provided one.
    private static let liveTranscriptText: @Sendable (String) -> String? = { uuid in
        let search = DataManager.sharedManager.transcriptSearch
        guard search.isAvailable else { return nil }
        // Qualified: the app module has its own (unrelated) TranscriptSource enum.
        for source in [PocketCastsDataModel.TranscriptSource.generated, .provided] {
            let texts = search.segments(episodeUuid: uuid, source: source).map(\.text)
            if !texts.isEmpty {
                return SpotlightItemBuilder.trimmedTextContent(texts)
            }
        }
        return nil
    }

    /// Only enriched bookmarks (Highlights) qualify; a plain bookmark's uuid
    /// resolves to nil and deletes any stale item.
    private static let liveResolveHighlight: @Sendable (String) -> SpotlightItemBuilder.HighlightMetadata? = { bookmarkUuid in
        guard let bookmark = DataManager.sharedManager.bookmarks.bookmark(for: bookmarkUuid),
              let excerpt = bookmark.excerpt else {
            return nil
        }
        return highlightMetadata(for: bookmark, excerpt: excerpt)
    }

    private static let liveAllHighlights: @Sendable () -> [SpotlightItemBuilder.HighlightMetadata] = {
        DataManager.sharedManager.bookmarks.allBookmarks()
            .compactMap { bookmark in
                bookmark.excerpt.map { highlightMetadata(for: bookmark, excerpt: $0) }
            }
    }

    private static func highlightMetadata(for bookmark: Bookmark, excerpt: String) -> SpotlightItemBuilder.HighlightMetadata {
        let episode = DataManager.sharedManager.findEpisode(uuid: bookmark.episodeUuid)
        let podcastUuid = bookmark.podcastUuid ?? episode?.podcastUuid
        return SpotlightItemBuilder.HighlightMetadata(
            bookmarkUuid: bookmark.uuid,
            title: bookmark.title,
            excerpt: excerpt,
            episodeTitle: episode?.title,
            podcastTitle: podcastUuid.flatMap { DataManager.sharedManager.findPodcast(uuid: $0, includeUnsubscribed: true)?.title }
        )
    }
}

nonisolated private extension Array {
    func chunked(size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
