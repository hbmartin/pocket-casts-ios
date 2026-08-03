import Combine
import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Drives the highlight editor sheet (Highlights program S4): title, tag set,
/// and — when a transcript exists — trimming the excerpt window with a
/// looping audio preview.
///
/// Saving re-derives the excerpt text from the cues intersecting the selected
/// range (so the stored text always matches the transcript) and stamps the
/// trim (ADR-0016), making the window authoritative over machine enrichment.
@MainActor
final class HighlightEditorViewModel: ObservableObject {
    struct LoadedTranscript: Sendable {
        let cues: [TranscriptCue]
        let plainText: String
        let usesReferenceTimeline: Bool
    }

    /// How far either side of the capture anchor the trim window can reach.
    static let windowReach: TimeInterval = 120

    let bookmark: Bookmark
    let episode: BaseEpisode?

    @Published var title: String
    @Published var tags: [String]
    @Published var tagInput: String = ""

    /// nil until the transcript loads; empty cues = no transcript (trim disabled).
    @Published private(set) var transcript: (cues: [TranscriptCue], plainText: String)?
    @Published private(set) var isLoadingTranscript = true
    @Published private(set) var isSaving = false
    @Published private(set) var saveFailed = false

    /// The editable window, absolute episode seconds. Only meaningful once the
    /// transcript has loaded.
    @Published var selectionStart: TimeInterval = 0
    @Published var selectionEnd: TimeInterval = 0

    /// The trim bar's pannable bounds around the capture anchor.
    private(set) var windowStart: TimeInterval = 0
    private(set) var windowEnd: TimeInterval = 0

    var analyticsSource: BookmarkAnalyticsSource = .unknown
    var onDismiss: (() -> Void)?

    private let bookmarkManager: BookmarkManager
    private let loadTranscript: @Sendable () async -> LoadedTranscript?
    private var usesReferenceTimeline = false

    /// The (recovered or default) selection when the sheet opened, for no-op detection.
    private var initialSelection: ClosedRange<TimeInterval>?
    private let initialTags: [String]

    init(manager: BookmarkManager,
         bookmark: Bookmark,
         loadTranscript: (@Sendable () async -> LoadedTranscript?)? = nil) {
        self.bookmarkManager = manager
        self.bookmark = bookmark
        self.episode = manager.episode(for: bookmark)
        self.title = bookmark.title
        self.tags = bookmark.tags
        self.initialTags = bookmark.tags

        let episodeUuid = bookmark.episodeUuid
        let podcastUuid = bookmark.podcastUuid ?? ""
        self.loadTranscript = loadTranscript ?? {
            let manager = TranscriptManager(episodeUUID: episodeUuid, podcastUUID: podcastUuid)
            guard let model = try? await manager.loadTranscript(), !model.cues.isEmpty else { return nil }
            return LoadedTranscript(
                cues: model.cues,
                plainText: model.plainText,
                usesReferenceTimeline: manager.isDisplayingGeneratedTranscript && !manager.isDisplayingLocalTranscription
            )
        }
    }

    var canTrim: Bool { transcript != nil }

    var suggestedTags: [String] {
        let existing = Set(tags.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) })
        return bookmarkManager.allTags().filter {
            !existing.contains($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil))
        }
    }

    /// The excerpt preview for the current selection (live while dragging).
    var selectionExcerpt: String? {
        guard let transcript, selectionEnd > selectionStart else { return bookmark.excerpt }
        return HighlightExcerptBuilder.excerpt(
            in: selectionStart...selectionEnd,
            cues: transcript.cues,
            plainText: transcript.plainText
        )?.text ?? bookmark.excerpt
    }

    func sheetAppeared() async {
        defer { isLoadingTranscript = false }
        guard let loaded = await loadTranscript() else { return }

        usesReferenceTimeline = loaded.usesReferenceTimeline
        guard let anchor = transcriptTime(forPlaybackTime: bookmark.time) else {
            // A server-generated transcript needs the active episode-bound
            // fingerprint alignment. Editing against raw playback seconds
            // would save and preview the wrong spoken passage.
            return
        }
        transcript = (loaded.cues, loaded.plainText)

        let duration = episode?.duration ?? .greatestFiniteMagnitude
        windowStart = max(0, anchor - Self.windowReach)
        windowEnd = min(duration > 0 ? duration : .greatestFiniteMagnitude, anchor + Self.windowReach)

        // Initial selection: the stored window when it can be recovered from the
        // persisted excerpt + endTime, else the machine default around the anchor.
        if let excerpt = bookmark.excerpt, let playbackEndTime = bookmark.endTime,
           let endTime = transcriptTime(forPlaybackTime: playbackEndTime),
           let recovered = HighlightExcerptBuilder.recoveredWindow(
               excerpt: excerpt, endTime: endTime,
               cues: loaded.cues, plainText: loaded.plainText
           ) {
            selectionStart = recovered.lowerBound
            selectionEnd = recovered.upperBound
        } else if let smart = HighlightExcerptBuilder.smartExcerpt(
            around: anchor, cues: loaded.cues, plainText: loaded.plainText
        ) {
            selectionStart = smart.startTime
            selectionEnd = smart.endTime
        } else {
            selectionStart = max(windowStart, anchor - HighlightExcerptBuilder.leadingWindow)
            selectionEnd = min(windowEnd, anchor + HighlightExcerptBuilder.trailingWindow)
        }
        // Keep the pannable bounds covering the recovered selection.
        windowStart = min(windowStart, selectionStart)
        windowEnd = max(windowEnd, selectionEnd)
        initialSelection = selectionStart...selectionEnd
    }

    func playbackTime(forTranscriptTime time: TimeInterval) -> TimeInterval? {
        guard usesReferenceTimeline else { return time }
        return FingerprintTimingManager.shared.playbackTime(
            forReferenceTime: time,
            episodeUuid: bookmark.episodeUuid
        )
    }

    func transcriptTime(forPlaybackTime time: TimeInterval) -> TimeInterval? {
        guard usesReferenceTimeline else { return time }
        return FingerprintTimingManager.shared.referenceTime(
            forPlaybackTime: time,
            episodeUuid: bookmark.episodeUuid
        )
    }

    // MARK: - Tags

    func addTag(_ raw: String? = nil) {
        let tag = (raw ?? tagInput).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }
        let key = tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        if !tags.contains(where: { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) == key }) {
            tags.append(tag)
            tags.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        tagInput = ""
    }

    func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }

    // MARK: - Saving

    func save() {
        guard !isSaving else { return }
        // Commit any half-typed tag so it isn't silently lost.
        addTag()
        saveFailed = false

        let trimmedTitle = String(title.trim().prefix(Constants.Values.bookmarkMaxTitleLength))
        let selection = (canTrim && selectionEnd > selectionStart) ? selectionStart...selectionEnd : nil
        let selectionChanged = selection != nil && selection != initialSelection
        let tagsChanged = tags != initialTags
        let titleChanged = trimmedTitle != bookmark.title && !trimmedTitle.isEmpty

        let trim: (excerpt: String, endTime: TimeInterval)?
        if selectionChanged, let selection, let transcript,
           let excerpt = HighlightExcerptBuilder.excerpt(
               in: selection, cues: transcript.cues, plainText: transcript.plainText
           ),
           let playbackEndTime = playbackTime(forTranscriptTime: excerpt.endTime) {
            trim = (excerpt.text, playbackEndTime)
        } else {
            trim = nil
        }

        if selectionChanged, trim == nil {
            saveFailed = true
            return
        }

        isSaving = true
        Task {
            var succeeded = true
            if titleChanged {
                let updated = await bookmarkManager.update(title: trimmedTitle, for: bookmark)
                succeeded = updated && succeeded
            }
            if tagsChanged {
                let updated = await bookmarkManager.setTags(tags, for: bookmark)
                succeeded = updated && succeeded
            }
            if let trim {
                // Store cue-snapped values: the assembled window's own bounds,
                // not the raw handle positions. endTime stays in the bookmark's
                // playback domain even when cues use reference time.
                let updated = await bookmarkManager.updateTrim(
                    excerpt: trim.excerpt,
                    endTime: trim.endTime,
                    for: bookmark
                )
                succeeded = updated && succeeded
            }

            isSaving = false
            guard succeeded else {
                saveFailed = true
                return
            }

            if titleChanged || tagsChanged || trim != nil {
                Analytics.track(.highlightEdited, properties: [
                    "source": analyticsSource.analyticsDescription,
                    "trimmed": trim != nil,
                    "tags_changed": tagsChanged,
                    "title_changed": titleChanged
                ])
            }

            onDismiss?()
        }
    }

    func cancel() {
        onDismiss?()
    }
}
