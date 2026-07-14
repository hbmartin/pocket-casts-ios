import Foundation
import Kingfisher
import PocketCastsDataModel
import PocketCastsUtils
import CoreMedia
import UIKit

enum ChapterOrigin {
    case podcastIndex
    case nativeMedia
    case generated
    case showNotes
    /// Synthesized progressively from AVPlayer timed metadata mid-stream.
    case streamedMetadata
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
        case .streamedMetadata:
            "streamed_metadata"
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

    /// Runs after a parse installs chapters and applies skip rules, so playback
    /// can skip a rule-deselected chapter that is already playing. Injected so
    /// tests can observe the call without a live `PlaybackManager`.
    private let currentChapterRevalidator: (BaseEpisode) -> Void

    private var playableChapters: [ChapterInfo] {
        visibleChapters.filter { $0.isPlayable() }
    }

    init(
        chapterParser: PodcastChapterParser = PodcastChapterParser(),
        showInfoCoordinator: ShowInfoCoordinating = ShowInfoCoordinator.shared,
        skipPatternsProvider: ((BaseEpisode) -> [String])? = nil,
        currentChapterRevalidator: ((BaseEpisode) -> Void)? = nil) {
        self.chapterParser = chapterParser
        self.showInfoCoordinator = showInfoCoordinator
        self.skipPatternsProvider = skipPatternsProvider ?? { episode in
            DataManager.sharedManager.findPodcast(uuid: episode.parentIdentifier())?.settings.skipChapterTitles ?? []
        }
        self.currentChapterRevalidator = currentChapterRevalidator ?? { episode in
            // A rule-skipped chapter may already be playing when parsing
            // finishes; without this the time observer only re-evaluates at the
            // next chapter boundary, so the whole unwanted chapter plays through.
            if PlaybackManager.shared.currentEpisode()?.uuid == episode.uuid {
                PlaybackManager.shared.playableChaptersUpdated()
            }
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
            fetchRemoteArtworkIfNeeded()
        }

        return hasChanged
    }

    // MARK: - Remote chapter artwork

    /// URLs with a fetch in flight or already failed this session — retried at
    /// most once per chapter load, never in a loop.
    private var artworkFetchesAttempted = Set<URL>()

    /// Resolves `imageURL`-only artwork (Podcast Index / Podlove chapters) for the
    /// current chapter and the next visible one (so the boundary crossing swaps
    /// art without a flash). A successful fetch lands in `chapter.image` — the
    /// slot every sink (player, mini player, lock screen, chapter list) reads —
    /// and re-posts the chapters-updated notification so they refresh.
    private func fetchRemoteArtworkIfNeeded() {
        let candidates = [currentChapters.visibleChapter, nextVisiblePlayableChapter()]
        for chapter in candidates {
            guard let chapter, chapter.image == nil, let url = chapter.imageURL,
                  !artworkFetchesAttempted.contains(url) else { continue }
            artworkFetchesAttempted.insert(url)

            KingfisherManager.shared.retrieveImage(with: url) { [weak self] result in
                guard let self, case .success(let value) = result else { return }
                Task { @MainActor [weak self] in
                    self?.applyFetchedArtwork(value.image, for: url)
                }
            }
        }
    }

    /// Lands a fetched artwork image in every chapter of the current list that
    /// shares `url` and is still missing art. Attempts are deduped by URL
    /// (`artworkFetchesAttempted`), so filling only the chapter that triggered
    /// the fetch would leave later same-URL chapters imageless forever — their
    /// boundary crossing would find the URL already attempted and never retry.
    func applyFetchedArtwork(_ image: UIImage, for url: URL) {
        var filled = [ChapterInfo]()
        for chapter in chapters where chapter.imageURL == url && chapter.image == nil {
            chapter.image = image
            filled.append(chapter)
        }
        // Only announce when the artwork is on screen; prefetched
        // next-chapter art gets announced by its boundary crossing.
        if filled.contains(where: { currentChapters.visibleChapter === $0 }) {
            NotificationCenter.postOnMainThread(PodcastChaptersDidUpdate())
        }
    }

    // MARK: - Streamed timed metadata

    /// Progressive chapter metadata pushed by AVPlayer mid-stream
    /// (`AVPlayerItemMetadataOutput`): artwork and titles that weren't available
    /// when the chapter list was parsed. Fills gaps in the chapter playing at
    /// `time` — embedded bytes still win — and, for an episode with no chapters
    /// at all, grows a synthetic list so timed metadata alone yields per-chapter
    /// art and titles.
    func ingestStreamedMetadata(title: String?, artworkData: Data?, at time: TimeInterval) {
        let artwork = artworkData.flatMap { UIImage(data: $0) }
        guard artwork != nil || !(title ?? "").isEmpty else { return }

        if chapters.isEmpty {
            appendStreamedChapter(title: title, artwork: artwork, at: time)
            return
        }

        // On a synthetic list the last chapter is open-ended, so it covers every
        // later time — a titled group meaningfully past the last boundary is a
        // new chapter, not a gap-fill of the current one.
        if chaptersOrigin == .streamedMetadata, let title, !title.isEmpty,
           let last = chapters.last, time > last.startTime.seconds + 1 {
            appendStreamedChapter(title: title, artwork: artwork, at: time)
            return
        }

        guard let chapter = chaptersForTime(time).visibleChapter else { return }
        var changed = false
        if let artwork, chapter.image == nil {
            chapter.image = artwork
            changed = true
        }
        if let title, !title.isEmpty, chapter.title.isEmpty {
            chapter.title = title
            changed = true
        }
        if changed, currentChapters.visibleChapter === chapter {
            NotificationCenter.postOnMainThread(PodcastChaptersDidUpdate())
        }
    }

    /// Appends a synthetic chapter starting at `time`, closing the previous
    /// synthetic chapter's open-ended duration at the new boundary.
    private func appendStreamedChapter(title: String?, artwork: UIImage?, at time: TimeInterval) {
        guard chapters.isEmpty || chaptersOrigin == .streamedMetadata else { return }

        if let last = chapters.last {
            // Metadata can re-announce the current group (seeks, output resets):
            // same boundary means update, not append.
            if abs(last.startTime.seconds - time) < 1 {
                if let artwork, last.image == nil { last.image = artwork }
                if let title, !title.isEmpty, last.title.isEmpty { last.title = title }
                NotificationCenter.postOnMainThread(PodcastChaptersDidUpdate())
                return
            }
            guard time > last.startTime.seconds else { return }
            last.duration = time - last.startTime.seconds
        }

        let chapter = ChapterInfo()
        chapter.title = title ?? ""
        chapter.image = artwork
        chapter.index = chapters.count
        chapter.startTime = CMTime(seconds: time, preferredTimescale: 1000000)
        // Open-ended until the next metadata group closes it.
        chapter.duration = .greatestFiniteMagnitude

        chaptersOrigin = .streamedMetadata
        chapters.append(chapter)
        updateCurrentChapter(time: PlaybackManager.shared.currentTime())
        NotificationCenter.postOnMainThread(PodcastChaptersDidUpdate())
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

        // Lowest precedence of all: when no source produced chapters, segment
        // the episode's own transcript on-device (Deferred Item 19; cached per
        // episode). Behaves as `.generated` downstream, like server-generated.
        // Only locally generated transcripts qualify: they are cut from the
        // exact audio being played, so their cue times align with playback.
        // Podcast-provided/server transcripts live on the reference timeline —
        // dynamic ads shift playback, so installing their cue times as chapter
        // starts makes chapters, seek and smart-skip drift. The flag is only
        // valid after `loadTranscript()` completes.
        if chapters.isEmpty, FeatureFlag.onDeviceChapters.enabled {
            let boxedManager = PocketCastsUtils.UncheckedSendable(
                TranscriptManager(episodeUUID: episodeUuid, podcastUUID: podcastUuid)
            )
            if let model = try? await Self.loadTranscript(boxedManager),
               boxedManager.value.isDisplayingLocalTranscription {
                let cues = SummaryTakeawayGenerator.timedCues(from: model)
                let generated = await TranscriptChapterGenerator().chapters(episodeUuid: episodeUuid, cues: cues, duration: duration)
                if !generated.isEmpty, lastEpisodeUuid == episode.uuid {
                    chapters = chapterParser.parseGeneratedChapters(generated, episodeDuration: duration)
                    chaptersOrigin = .generated
                    FileLog.shared.addMessage("ChapterManager: using on-device generated chapters")
                }
            }
        }

        if lastEpisodeUuid == episode.uuid {
            handleChaptersLoaded(chapters, for: episode)
        }
    }

    nonisolated private static func loadTranscript(
        _ manager: PocketCastsUtils.UncheckedSendable<TranscriptManager>
    ) async throws -> TranscriptModel {
        try await manager.value.loadTranscript()
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
        artworkFetchesAttempted.removeAll()

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

        artworkFetchesAttempted.removeAll()
        updateCurrentChapter(time: PlaybackManager.shared.currentTime())
        fetchRemoteArtworkIfNeeded()

        currentChapterRevalidator(episode)

        NotificationCenter.postOnMainThread(PodcastChaptersDidUpdate())
    }
}
