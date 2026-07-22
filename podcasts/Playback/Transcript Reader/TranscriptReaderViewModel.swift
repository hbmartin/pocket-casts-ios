import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Drives the full-screen transcript reader: follow-along cue highlighting,
/// in-reader search, tap-to-seek, and quote/clip share payload assembly.
///
/// The fingerprint timing calls are injected (`TimingProvider`) so the
/// cue-resolution and seek logic can be unit tested with a stubbed mapping.
@MainActor
final class TranscriptReaderViewModel: ObservableObject {

    // MARK: - Types

    /// Facade over `FingerprintTimingManager` so tests can stub the mapping.
    struct TimingProvider {
        var isActive: () -> Bool
        var isUnavailable: () -> Bool
        /// Same call the transcript view controller's highlight loop uses.
        var matchedReferenceTime: (Double) -> Double?
        /// Same call the transcript view controller's tap-to-seek uses.
        var playbackTime: (Double) -> Double?

        static var fingerprint: TimingProvider {
            TimingProvider(
                isActive: {
                    if case .active = FingerprintTimingManager.shared.state { return true }
                    return false
                },
                isUnavailable: {
                    if case .unavailable = FingerprintTimingManager.shared.state { return true }
                    return false
                },
                matchedReferenceTime: { FingerprintTimingManager.shared.matchedReferenceTime(forPlaybackTime: $0) },
                playbackTime: { FingerprintTimingManager.shared.playbackTime(forReferenceTime: $0) }
            )
        }
    }

    enum SeekOutcome: Equatable {
        case seeked(to: TimeInterval)
        /// Seeking isn't possible here (mirrors the VC's `canSeek` guard).
        case notAllowed
        /// Fingerprint mapping unavailable; stay silent (mirrors the VC).
        case mappingUnavailable
        /// Mapping missing but downloading would enable it; show the same
        /// "download to seek" toast the VC shows.
        case downloadRequiredHint
    }

    struct SearchMatch: Equatable {
        /// Ordinal of this match across the whole transcript (navigation order).
        let matchIndex: Int
        let blockID: Int
        /// Character offsets within the block's (trimmed) `text`.
        let characterRange: Range<Int>
    }

    // MARK: - Content

    let transcript: TranscriptModel
    let blocks: [TranscriptReaderBlock]
    let episodeTitle: String?
    let episodeShareURLString: String?
    let isGeneratedTranscript: Bool
    /// Locally generated (on-device) transcript: cut from the exact audio file
    /// being played, so cue times ARE playback times and no fingerprint mapping
    /// applies (mirrors the VC's `isDisplayingLocalTranscription` handling).
    let isLocalTranscript: Bool

    // MARK: - Published state

    /// Block id of the cue currently being spoken, when follow-along is active.
    @Published private(set) var currentCueBlockID: Int?
    /// Whether the reader auto-scrolls to keep the current cue in view.
    @Published private(set) var isFollowing = true
    @Published private(set) var searchTerm: String = ""
    @Published private(set) var matches: [SearchMatch] = []
    @Published private(set) var currentMatchIndex: Int = 0
    /// Matches grouped by block id, for per-block highlight rendering.
    @Published private(set) var matchesByBlock: [Int: [SearchMatch]] = [:]

    // MARK: - Private

    private let playback: TranscriptPlaybackManaging
    private let timing: TimingProvider
    private let isEpisodeDownloaded: @MainActor () -> Bool
    private var cueTracker = TranscriptCueTracker()
    private var blockIDByCueIndex: [Int: Int] = [:]
    /// One searcher per block, built lazily on first search (mirrors how the
    /// VC caches its single `KMPSearch`).
    private var blockSearchers: [KMPSearch]?
    private var autoResumeTask: Task<Void, Never>?

    /// Matches `TranscriptViewController.autoScrollBackDelay`.
    static let autoResumeDelay: TimeInterval = 5.0

    // MARK: - Init

    init(transcript: TranscriptModel,
         playback: TranscriptPlaybackManaging,
         isGeneratedTranscript: Bool,
         isLocalTranscript: Bool = false,
         episodeTitle: String?,
         episodeShareURLString: String?,
         timing: TimingProvider = .fingerprint,
         isEpisodeDownloaded: (@MainActor () -> Bool)? = nil) {
        self.transcript = transcript
        self.playback = playback
        self.isGeneratedTranscript = isGeneratedTranscript
        self.isLocalTranscript = isLocalTranscript
        self.episodeTitle = episodeTitle
        self.episodeShareURLString = episodeShareURLString
        self.timing = timing
        self.isEpisodeDownloaded = isEpisodeDownloaded ?? { [episodeUUID = playback.episodeUUID] in
            // Mirrors the VC's tap-to-seek fallback check.
            guard let episodeUUID,
                  let episode = DataManager.sharedManager.findBaseEpisode(uuid: episodeUUID),
                  let status = DownloadStatus(rawValue: episode.episodeStatus) else {
                return false
            }
            return status == .downloaded || status == .downloadedForStreaming
        }

        let blocks = TranscriptReaderContent.makeBlocks(from: transcript)
        self.blocks = blocks
        for block in blocks {
            if let cueIndex = block.cueIndex {
                blockIDByCueIndex[cueIndex] = block.id
            }
        }
    }

    // isolated deinit: view models deallocate on the main actor; cancels an isolated task handle
    isolated deinit {
        autoResumeTask?.cancel()
    }

    // MARK: - Follow-along highlighting

    /// Called at ~4 Hz by the view's timer. For locally generated transcripts
    /// the raw playback time is the cue timeline (mirrors the VC's
    /// `updateTranscriptPosition` local branch). Otherwise highlighting is
    /// opt-in exactly like the VC's display-link loop: only while the
    /// fingerprint manager is `.active` and playback maps onto matched
    /// reference content; otherwise the highlight clears.
    func refreshCurrentCue() {
        if isLocalTranscript {
            updateCurrentCue(forReferenceTime: playback.currentTime())
            return
        }
        guard timing.isActive(), let reference = timing.matchedReferenceTime(playback.currentTime()) else {
            if currentCueBlockID != nil {
                currentCueBlockID = nil
            }
            return
        }
        updateCurrentCue(forReferenceTime: reference)
    }

    /// Resolves the highlighted cue for an explicit reference time. Split from
    /// `refreshCurrentCue()` so tests can drive the cue-resolution math directly.
    func updateCurrentCue(forReferenceTime reference: Double) {
        if let cueIndex = cueTracker.cueIndex(at: reference, in: transcript.cues) {
            let blockID = blockIDByCueIndex[cueIndex]
            if currentCueBlockID != blockID {
                currentCueBlockID = blockID
            }
        } else if let firstCue = transcript.cues.first, reference < firstCue.startTime {
            // Before the first cue there is nothing to highlight (mirrors the VC).
            if currentCueBlockID != nil {
                currentCueBlockID = nil
            }
        }
        // Between cues: keep the previous highlight (mirrors the VC).
    }

    // MARK: - Follow state

    /// The user scrolled away: stop following and schedule the same 5s
    /// scroll-back the VC uses (which only fires while audio is playing).
    func noteUserScrolled() {
        isFollowing = false
        autoResumeTask?.cancel()
        autoResumeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.autoResumeDelay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            // Only catch up to the highlight if audio is moving (mirrors the VC:
            // when paused, snapping back would fight a deliberate scroll-away).
            guard self.playback.isPlayingEpisode else { return }
            self.isFollowing = true
        }
    }

    func resumeFollowing() {
        autoResumeTask?.cancel()
        autoResumeTask = nil
        isFollowing = true
    }

    // MARK: - Seeking

    /// Mirrors `TranscriptViewController.transcriptTapped(_:)`. For generated
    /// non-local transcripts the cue time is on the fingerprint reference
    /// timeline and must be mapped; local and external transcripts are authored
    /// against the episode audio itself, so their cue time is already playback
    /// time.
    func seek(toCueIndex cueIndex: Int) -> SeekOutcome {
        guard playback.canSeek, transcript.cues.indices.contains(cueIndex) else {
            return .notAllowed
        }
        let cue = transcript.cues[cueIndex]

        guard isGeneratedTranscript, !isLocalTranscript else {
            playback.seekTo(time: cue.startTime)
            return .seeked(to: cue.startTime)
        }

        guard let seekTime = timing.playbackTime(cue.startTime) else {
            if timing.isUnavailable() { return .mappingUnavailable }
            if isEpisodeDownloaded() { return .mappingUnavailable }
            return .downloadRequiredHint
        }

        playback.seekTo(time: seekTime)
        return .seeked(to: seekTime)
    }

    // MARK: - Search

    func search(term: String) {
        searchTerm = term
        guard !term.isEmpty else {
            clearSearchResults()
            return
        }

        if blockSearchers == nil {
            blockSearchers = blocks.map { KMPSearch(text: $0.text) }
        }

        let termLength = term.count
        var found: [SearchMatch] = []
        var byBlock: [Int: [SearchMatch]] = [:]
        for (blockIndex, searcher) in (blockSearchers ?? []).enumerated() {
            let blockID = blocks[blockIndex].id
            for start in searcher.search(for: term) {
                let match = SearchMatch(matchIndex: found.count, blockID: blockID, characterRange: start ..< (start + termLength))
                found.append(match)
                byBlock[blockID, default: []].append(match)
            }
        }
        matches = found
        matchesByBlock = byBlock
        currentMatchIndex = 0
    }

    func clearSearch() {
        searchTerm = ""
        clearSearchResults()
    }

    private func clearSearchResults() {
        matches = []
        matchesByBlock = [:]
        currentMatchIndex = 0
    }

    var currentMatch: SearchMatch? {
        matches.indices.contains(currentMatchIndex) ? matches[currentMatchIndex] : nil
    }

    /// Wraps around, mirroring the VC's `updateCurrentSearchIndex(decrement:)`.
    func nextMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matches.count
    }

    func previousMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matches.count) % matches.count
    }

    // MARK: - Sharing

    /// The share-sheet text for quoting a paragraph block. Generated-transcript
    /// cue times are mapped to the playback timeline (as `seek` does); when no
    /// mapping is available the quote is shared without a timestamp rather than
    /// with one that lands on different audio.
    func quoteText(forBlock blockID: Int) -> String? {
        guard blocks.indices.contains(blockID) else { return nil }
        let block = blocks[blockID]
        guard case .paragraph(let cueIndex) = block.kind else { return nil }
        let startTime = cueIndex
            .flatMap { transcript.cues.indices.contains($0) ? transcript.cues[$0].startTime : nil }
            .flatMap { playbackTimelineTime(forCueTime: $0) }
        return TranscriptQuoteBuilder.quoteText(
            cueText: block.text,
            episodeTitle: episodeTitle,
            shareURLString: episodeShareURLString,
            startTime: startTime
        )
    }

    /// The raw line + anchor data for quoting into a comment (Slice 12).
    /// Unlike `quoteText` this is the unformatted line: the quote text is
    /// stored verbatim on the comment. A generated transcript without an
    /// active mapping yields a nil timestamp — the composer then stamps the
    /// current playback position at send.
    func commentQuote(forBlock blockID: Int) -> (text: String, timestampSeconds: Int?, segment: Int)? {
        guard blocks.indices.contains(blockID),
              let cueIndex = blocks[blockID].cueIndex else { return nil }
        let time = transcript.cues.indices.contains(cueIndex)
            ? playbackTimelineTime(forCueTime: transcript.cues[cueIndex].startTime) : nil
        let text = blocks[blockID].text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return (text, time.map { Int($0) }, cueIndex)
    }

    /// The cue's time window on the playback timeline, for pre-seeding the
    /// clip-share flow. Returns nil for a generated transcript without an
    /// active mapping — a clip trimmed against unmapped reference times would
    /// cut the wrong audio.
    func clipRange(forBlock blockID: Int) -> (start: TimeInterval, end: TimeInterval)? {
        guard blocks.indices.contains(blockID),
              let cueIndex = blocks[blockID].cueIndex,
              transcript.cues.indices.contains(cueIndex) else {
            return nil
        }
        let cue = transcript.cues[cueIndex]
        guard cue.endTime > cue.startTime,
              let start = playbackTimelineTime(forCueTime: cue.startTime),
              let end = playbackTimelineTime(forCueTime: cue.endTime),
              end > start else { return nil }
        return (start, end)
    }

    /// Converts a cue-timeline time to the playback timeline: identity for
    /// external and locally generated transcripts, fingerprint-mapped for
    /// remote generated ones (the same conversion `seek` applies).
    private func playbackTimelineTime(forCueTime time: TimeInterval) -> TimeInterval? {
        guard isGeneratedTranscript, !isLocalTranscript else { return time }
        return timing.playbackTime(time)
    }
}
