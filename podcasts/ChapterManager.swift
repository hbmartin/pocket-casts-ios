import Foundation
import PocketCastsDataModel
import PocketCastsUtils
import CoreMedia

enum ChapterOrigin {
    case podcastIndex
    case nativeMedia
    case generated
    case showNotes
    case unknown

    var analyticsDescription: String {
        switch self {
        case .generated:
            "generated"
        case .nativeMedia:
            "native_media"
        case .showNotes:
            "show_notes"
        case .podcastIndex:
            "podcast_index"
        case .unknown:
            "unknown"
        }
    }
}

@MainActor
class ChapterManager {
    // Explicitly nonisolated: default-MainActor synthesized deinits hop executors and crash sync XCTests (swiftlang/swift#87316).
    nonisolated deinit {}
    private var chapterParser = PodcastChapterParser()
    private var showInfoCoordinator: ShowInfoCoordinating
    private var chapters = [ChapterInfo]() {
        didSet {
            visibleChapters = chapters.filter { !$0.isHidden }
        }
    }
    private var visibleChapters = [ChapterInfo]()

    private var lastEpisodeUuid = ""

    var numberOfChaptersSkipped = 0

    var currentChapters = Chapters()

    var chaptersOrigin: ChapterOrigin = .unknown

    /// Chapter indices deselected by the podcast's smart-skip title rules for the currently
    /// loaded chapter list (excludes chapters the user deselected manually). Used for analytics.
    private(set) var ruleSkippedIndices = Set<Int>()

    /// Session-only exceptions to the smart-skip rules, keyed by episode uuid: when the user
    /// re-enables a rule-skipped chapter in the chapters UI the index lands here so reloading
    /// chapters doesn't re-deselect it. Re-enables last for the app session only; permanent
    /// per-episode exceptions are a future refinement.
    private var sessionReEnabledChapters = [String: Set<Int>]()

    /// Resolves the smart-skip title patterns for an episode's podcast. Injectable for tests.
    private let skipPatternsProvider: (BaseEpisode) -> [String]

    private var playableChapters: [ChapterInfo] {
        visibleChapters.filter { $0.isPlayable() }
    }

    init(
        chapterParser: PodcastChapterParser = PodcastChapterParser(),
        showInfoCoordinator: ShowInfoCoordinating = ShowInfoCoordinator.shared,
        skipPatternsProvider: ((BaseEpisode) -> [String])? = nil) {
        self.chapterParser = chapterParser
        self.showInfoCoordinator = showInfoCoordinator
        self.skipPatternsProvider = skipPatternsProvider ?? { episode in
            DataManager.sharedManager.findPodcast(uuid: episode.parentIdentifier())?.settings.skipChapterTitles ?? []
        }
    }

    /// Records that the user re-enabled a chapter so smart-skip rules leave it alone for the
    /// rest of the session, even if the chapter list reloads.
    func registerSessionReEnable(chapterIndex: Int, episodeUuid: String) {
        sessionReEnabledChapters[episodeUuid, default: []].insert(chapterIndex)
        ruleSkippedIndices.remove(chapterIndex)
    }

    /// Removes a session re-enable exception (the user deselected the chapter again).
    func unregisterSessionReEnable(chapterIndex: Int, episodeUuid: String) {
        sessionReEnabledChapters[episodeUuid]?.remove(chapterIndex)
    }

    /// Whether the given chapter index was deselected by a smart-skip rule (not by the user).
    func isRuleSkipped(chapterIndex: Int) -> Bool {
        ruleSkippedIndices.contains(chapterIndex)
    }

    func visibleChapterCount() -> Int {
        visibleChapters.count
    }

    func playableChapterCount() -> Int {
        playableChapters.count
    }

    func haveTriedToParseChaptersFor(episodeUuid: String?) -> Bool {
        lastEpisodeUuid == episodeUuid
    }

    func previousVisibleChapter() -> ChapterInfo? {
        guard let visibleChapter = currentChapters.visibleChapter else {
            return nil
        }
        let previousChapter: ChapterInfo?

        if let index = visibleChapters.firstIndex(of: visibleChapter) {
            previousChapter = visibleChapters.enumerated().filter { $0.offset < index && $0.element.isPlayable() }.map { $0.element }.last
        } else {
            previousChapter = nil
        }
        return previousChapter
    }

    func nextVisiblePlayableChapter() -> ChapterInfo? {
        guard let visibleChapter = currentChapters.visibleChapter else {
            return nil
        }
        let nextChapter: ChapterInfo?

        if let index = visibleChapters.firstIndex(of: visibleChapter) {
            nextChapter = visibleChapters.enumerated().first { $0.offset > index && $0.element.isPlayable() }.map { $0.element }
        } else {
            nextChapter = nil
        }
        return nextChapter
    }

    var lastChapter: ChapterInfo? {
        visibleChapters.last
    }

    func chapterAt(index: Int) -> ChapterInfo? {
        visibleChapters[safe: index]
    }

    func playableChapterAt(index: Int) -> ChapterInfo? {
        visibleChapters.filter({ $0.isPlayable() })[safe: index]
    }

    func index(for chapter: Chapters) -> Int? {
        guard let visibleChapter = chapter.visibleChapter else {
            return nil
        }

        return playableChapters.firstIndex(of: visibleChapter)
    }

    @discardableResult
    func updateCurrentChapter(time: TimeInterval) -> Bool {
        if chapters.isEmpty { return false }

        let chapters = chaptersForTime(time)
        let hasChanged = currentChapters != chapters

        if hasChanged {
            currentChapters = chapters
        }

        return hasChanged
    }

    func parseChapters(episode: BaseEpisode, duration: TimeInterval) {
        // The manager and episode cross into the parse task boxed; parsing is
        // bounded, so briefly retaining the manager is harmless
        let boxed = PocketCastsUtils.UncheckedSendable((self, episode))
        Task.detached {
            let (manager, episode) = boxed.value
            await manager.parseChapters(episode: episode, duration: duration)
        }
    }

    func parseChapters(episode: BaseEpisode, duration: TimeInterval) async {
        // store the last episode uuid we were asked to check chapters for, we use that below in case this method is called multiple times to not return old results
        lastEpisodeUuid = episode.uuid

        try? await parseLocalAndRemoteChapters(for: episode, duration: duration)
    }

    private func parseLocalAndRemoteChapters(for episode: BaseEpisode, duration: TimeInterval) async throws {
        // Parse chapters from the file and request external chapters. The child
        // tasks take their non-Sendable inputs boxed
        let boxed = PocketCastsUtils.UncheckedSendable((self, episode))
        let boxedCoordinator = PocketCastsUtils.UncheckedSendable(showInfoCoordinator)
        let podcastUuid = episode.parentIdentifier()
        let episodeUuid = episode.uuid

        async let fileChaptersAsync = Self.loadFileChapters(boxed, duration: duration)

        async let externalChaptersAsync = Self.loadExternalChapters(
            boxedCoordinator,
            podcastUuid: podcastUuid,
            episodeUuid: episodeUuid
        )

        var chapters: [ChapterInfo]

        do {
            let (fileChapters, externalChaptersResult) = try await (fileChaptersAsync, externalChaptersAsync)

            // Prioritize embedded chapters, given for some shows it will take
            // into account dynamic ads
            if !fileChapters.isEmpty {
                chapters = fileChapters
                FileLog.shared.addMessage("ChapterManager: using file chapters")
                chaptersOrigin = .nativeMedia
            } else if let externalChapters = parseExternalChapters(podlove: externalChaptersResult.metadata, podcastIndex: externalChaptersResult.podcastIndex, generated: externalChaptersResult.generated, duration: duration) {
                chapters = externalChapters
                FileLog.shared.addMessage("ChapterManager: using external chapters")
            } else {
                chapters = []
                FileLog.shared.addMessage("ChapterManager: failed. Displaying no chapters.")
            }
        } catch {
            chapters = await fileChaptersAsync
            chaptersOrigin = chapters.isEmpty ? .unknown : .nativeMedia
            FileLog.shared.addMessage("ChapterManager: using file chapters because there was an error retrieving external sources")
        }

        if lastEpisodeUuid == episode.uuid {
            handleChaptersLoaded(chapters, for: episode)
        }
    }

    nonisolated private static func loadFileChapters(_ boxed: PocketCastsUtils.UncheckedSendable<(ChapterManager, BaseEpisode)>, duration: TimeInterval) async -> [ChapterInfo] {
        let (manager, episode) = boxed.value
        return await manager.loadChapters(for: episode, duration: duration)
    }

    nonisolated private static func loadExternalChapters(_ boxedCoordinator: PocketCastsUtils.UncheckedSendable<any ShowInfoCoordinating>, podcastUuid: String, episodeUuid: String) async throws -> (metadata: [Episode.Metadata.EpisodeChapter]?, podcastIndex: [PodcastIndexChapter]?, generated: [GeneratedChapter]?) {
        try await boxedCoordinator.value.loadChapters(
            podcastUuid: podcastUuid,
            episodeUuid: episodeUuid
        )
    }

    nonisolated private func loadChapters(for episode: BaseEpisode, duration: TimeInterval) async -> [ChapterInfo] {
        if episode.downloaded(pathFinder: DownloadManager.shared) {
            return await chapterParser.parseLocalFile(episode.pathToDownloadedFile(pathFinder: DownloadManager.shared), episodeDuration: duration)
        } else if let url = EpisodeManager.urlForEpisode(episode) {
            return await chapterParser.parseRemoteFile(url.absoluteString, episodeDuration: duration)
        }

        return []
    }

    private func parseExternalChapters(podlove: [Episode.Metadata.EpisodeChapter]?, podcastIndex: [PodcastIndexChapter]?, generated: [GeneratedChapter]?, duration: TimeInterval) -> [ChapterInfo]? {
        if let podcastIndex {
            chaptersOrigin = .podcastIndex
            return chapterParser.parsePodcastIndexChapters(podcastIndex, episodeDuration: duration)
        }

        if let podlove {
            chaptersOrigin = .showNotes
            return chapterParser.parsePodloveChapters(podlove, episodeDuration: duration)
        }

        if let generated {
            chaptersOrigin = .generated
            return chapterParser.parseGeneratedChapters(generated, episodeDuration: duration)
        }

        chaptersOrigin = .unknown
        return nil
    }

    func clearChapterInfo() {
        lastEpisodeUuid = ""
        chapters.removeAll()
        currentChapters = Chapters()
        chaptersOrigin = .unknown
        ruleSkippedIndices.removeAll()

        NotificationCenter.postOnMainThread(PodcastChaptersDidUpdate())
    }

    func chaptersForTime(_ time: TimeInterval) -> Chapters {
        Chapters(chapters: chapters.filter { $0.startTime.seconds <= time && ($0.startTime.seconds + $0.duration) > time })
    }

    var chaptersAnalyticsProperties: [String: Any] {
        return ["origin": chaptersOrigin.analyticsDescription]
    }

    private func handleChaptersLoaded(_ chapters: [ChapterInfo], for episode: BaseEpisode) {
        self.chapters = chapters

        episode.deselectedChapters?
            .split(separator: ",")
            .compactMap { Int($0) }
            .forEach { self.chapters[safe: $0]?.shouldPlay = false }

        // Smart skip runs after the merged sources and the user's manual deselections are applied:
        // rule-matched chapters auto-deselect unless re-enabled by the user this session.
        ruleSkippedIndices = ChapterSkipRules.apply(
            to: self.chapters,
            patterns: skipPatternsProvider(episode),
            reEnabledIndices: sessionReEnabledChapters[episode.uuid] ?? [])

        updateCurrentChapter(time: PlaybackManager.shared.currentTime())

        NotificationCenter.postOnMainThread(PodcastChaptersDidUpdate())
    }
}
