import Combine
import Foundation
import PocketCastsDataModel
import PocketCastsFileSync
import PocketCastsUtils

/// Auto-exports highlights as Markdown into a user-picked folder (an Obsidian
/// vault, iCloud Drive, …) — Highlights program S5.
///
/// One file per episode (`<Podcast>/<Episode>--<Episode UUID>.md`), app-owned and rewritten
/// whole on change: bookmark create/edit/trim/tag/delete events mark the
/// episode dirty, and a short debounce coalesces bursts before writing.
/// Folder access reuses the file-sync security-scoped machinery
/// (`BookmarkSyncFolder`), so stale bookmarks self-heal and every write is
/// NSFileCoordinator-coordinated.
@MainActor
final class HighlightFolderExporter {
    static let shared = HighlightFolderExporter()

    private static let folderBookmarkKey = "highlightExport.folderBookmark"
    private static let episodePathsKey = "highlightExport.episodePaths"
    private static let pathFormatVersionKey = "highlightExport.pathFormatVersion"
    private static let currentPathFormatVersion = 2
    private static let debounceInterval: TimeInterval = 3
    private static let retryInterval: TimeInterval = 30

    private var cancellables = Set<AnyCancellable>()
    private var dirtyEpisodes = Set<String>()
    private var drainTask: Task<Void, Never>?
    private var isMigratingPaths = false

    private let bookmarkManager: BookmarkManager

    init(bookmarkManager: BookmarkManager = PlaybackManager.shared.bookmarkManager) {
        self.bookmarkManager = bookmarkManager
    }

    // MARK: - Configuration

    var isEnabled: Bool {
        UserDefaults.standard.data(forKey: Self.folderBookmarkKey) != nil
    }

    /// The picked folder's display name for the settings row.
    var folderDisplayName: String? {
        guard let data = UserDefaults.standard.data(forKey: Self.folderBookmarkKey) else { return nil }
        var stale = false
        let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
        return url?.lastPathComponent
    }

    /// Called from the folder picker delegate (inside the implicit access window).
    func enable(pickedFolder url: URL) throws {
        let data = try BookmarkSyncFolder.makeBookmarkData(forPickedFolder: url)
        UserDefaults.standard.set(data, forKey: Self.folderBookmarkKey)
        startObservingIfNeeded()
        exportAll()
        Analytics.track(.highlightExportFolderEnabled)
    }

    func disable() {
        UserDefaults.standard.removeObject(forKey: Self.folderBookmarkKey)
        drainTask?.cancel()
        dirtyEpisodes.removeAll()
        Analytics.track(.highlightExportFolderDisabled)
    }

    // MARK: - Lifecycle

    /// Idempotent; called at app start (flag-gated) and when the folder is picked.
    func startObservingIfNeeded() {
        guard FeatureFlag.pkmExport.enabled, isEnabled, cancellables.isEmpty else { return }

        bookmarkManager.onBookmarkCreated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in self?.markDirty(episodeUuid: event.episode) }
            .store(in: &cancellables)

        bookmarkManager.onBookmarkChanged
            .receive(on: DispatchQueue.main)
            .compactMap { [weak self] event in self?.bookmarkManager.bookmark(for: event.uuid)?.episodeUuid }
            .sink { [weak self] episodeUuid in self?.markDirty(episodeUuid: episodeUuid) }
            .store(in: &cancellables)

        bookmarkManager.onBookmarksDeleted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                event.items.forEach { self?.markDirty(episodeUuid: $0.episode) }
            }
            .store(in: &cancellables)

        if UserDefaults.standard.integer(forKey: Self.pathFormatVersionKey) < Self.currentPathFormatVersion {
            isMigratingPaths = true
            exportAll()
        }
    }

    /// Queues every episode that has highlights (initial export, or catch-up
    /// from the background-refresh hook).
    func exportAll() {
        guard FeatureFlag.pkmExport.enabled, isEnabled else { return }
        for bookmark in bookmarkManager.allBookmarks() {
            dirtyEpisodes.insert(bookmark.episodeUuid)
        }
        scheduleDrain(after: 0)
    }

    private func markDirty(episodeUuid: String) {
        guard isEnabled else { return }
        dirtyEpisodes.insert(episodeUuid)
        scheduleDrain(after: Self.debounceInterval)
    }

    private func scheduleDrain(after delay: TimeInterval) {
        drainTask?.cancel()
        drainTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            await self?.drain()
        }
    }

    // MARK: - Writing

    private func drain() async {
        guard let data = UserDefaults.standard.data(forKey: Self.folderBookmarkKey) else { return }

        let episodes = dirtyEpisodes
        dirtyEpisodes.removeAll()
        guard !episodes.isEmpty else { return }

        let renderer = HighlightMarkdownRenderer()
        let folder = BookmarkSyncFolder(bookmarkData: data)
        var episodePaths = rememberedEpisodePaths
        var failedEpisodes = Set<String>()
        var written = 0

        for episodeUuid in episodes {
            let previousPath = episodePaths[episodeUuid]
            let resolvedExport = resolveExport(episodeUuid: episodeUuid)
            guard let export = resolvedExport, !export.highlights.isEmpty else {
                let stalePaths = Set([previousPath, resolvedExport.map(renderer.legacyRelativePath)].compactMap { $0 })
                guard !stalePaths.isEmpty else { continue }
                do {
                    for stalePath in stalePaths {
                        try await folder.coordinatedDelete(stalePath)
                    }
                    episodePaths.removeValue(forKey: episodeUuid)
                } catch {
                    failedEpisodes.insert(episodeUuid)
                    FileLog.shared.addMessage("[HighlightExport] delete failed for \(episodeUuid): \(error)")
                }
                continue
            }

            let currentPath = renderer.relativePath(for: export)
            guard let contents = renderer.markdown(for: export).data(using: .utf8) else {
                failedEpisodes.insert(episodeUuid)
                continue
            }

            do {
                let directory = (currentPath as NSString).deletingLastPathComponent
                if !directory.isEmpty {
                    try await folder.createDirectory(directory)
                }
                try await folder.coordinatedWrite(currentPath, data: contents)

                // Only remove old paths after the replacement is durable. This
                // covers title/podcast renames and migrates the original
                // collision-prone filename format.
                let stalePaths = Set([previousPath, renderer.legacyRelativePath(for: export)].compactMap { $0 })
                    .subtracting([currentPath])
                for stalePath in stalePaths {
                    try await folder.coordinatedDelete(stalePath)
                }

                episodePaths[episodeUuid] = currentPath
                written += 1
            } catch {
                failedEpisodes.insert(episodeUuid)
                FileLog.shared.addMessage("[HighlightExport] update failed for \(currentPath): \(error)")
            }
        }

        rememberedEpisodePaths = episodePaths

        // A resolved stale bookmark self-heals for next time.
        if let refreshed = await folder.refreshedBookmarkData {
            UserDefaults.standard.set(refreshed, forKey: Self.folderBookmarkKey)
        }
        if written > 0 {
            Analytics.track(.highlightExportWritten, properties: ["files": written])
        }
        if !failedEpisodes.isEmpty {
            dirtyEpisodes.formUnion(failedEpisodes)
            scheduleDrain(after: Self.retryInterval)
        } else if isMigratingPaths {
            UserDefaults.standard.set(Self.currentPathFormatVersion, forKey: Self.pathFormatVersionKey)
            isMigratingPaths = false
        }
    }

    private var rememberedEpisodePaths: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: Self.episodePathsKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.episodePathsKey) }
    }

    private func resolveExport(episodeUuid: String) -> HighlightMarkdownRenderer.EpisodeExport? {
        guard let episode = DataManager.sharedManager.findBaseEpisode(uuid: episodeUuid) else { return nil }

        let bookmarks = bookmarkManager.bookmarks(for: episode, sorted: .timestamp)
        let podcastTitle: String
        if let episode = episode as? Episode {
            podcastTitle = DataManager.sharedManager.findPodcast(uuid: episode.podcastUuid)?.title ?? L10n.bookmarksExportUnknownPodcast
        } else {
            podcastTitle = L10n.files
        }

        let highlights = bookmarks.map { bookmark in
            HighlightMarkdownRenderer.ResolvedHighlight(
                title: bookmark.title,
                time: bookmark.time,
                endTime: bookmark.endTime,
                created: bookmark.created,
                excerpt: bookmark.excerpt,
                tags: bookmark.tags,
                shareLink: (episode as? Episode).map { $0.shareURL + "?t=\(Int(bookmark.time.rounded()))" }
            )
        }

        return HighlightMarkdownRenderer.EpisodeExport(
            podcastTitle: podcastTitle,
            episodeTitle: episode.displayableTitle(),
            episodeUuid: episodeUuid,
            highlights: highlights
        )
    }
}
