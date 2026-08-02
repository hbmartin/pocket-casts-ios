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
    private let loadTranscript: @Sendable () async -> (cues: [TranscriptCue], plainText: String)?

    /// The (recovered or default) selection when the sheet opened, for no-op detection.
    private var initialSelection: ClosedRange<TimeInterval>?
    private let initialTags: [String]

    init(manager: BookmarkManager,
         bookmark: Bookmark,
         loadTranscript: (@Sendable () async -> (cues: [TranscriptCue], plainText: String)?)? = nil) {
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
            return (cues: model.cues, plainText: model.plainText)
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
        transcript = loaded

        let anchor = bookmark.time
        let duration = episode?.duration ?? .greatestFiniteMagnitude
        windowStart = max(0, anchor - Self.windowReach)
        windowEnd = min(duration > 0 ? duration : .greatestFiniteMagnitude, anchor + Self.windowReach)

        // Initial selection: the stored window when it can be recovered from the
        // persisted excerpt + endTime, else the machine default around the anchor.
        if let excerpt = bookmark.excerpt, let endTime = bookmark.endTime,
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
        // Commit any half-typed tag so it isn't silently lost.
        addTag()

        let trimmedTitle = String(title.trim().prefix(Constants.Values.bookmarkMaxTitleLength))
        let selection = (canTrim && selectionEnd > selectionStart) ? selectionStart...selectionEnd : nil
        let selectionChanged = selection != nil && selection != initialSelection
        let tagsChanged = tags != initialTags
        let titleChanged = trimmedTitle != bookmark.title && !trimmedTitle.isEmpty

        Task {
            if titleChanged {
                await bookmarkManager.update(title: trimmedTitle, for: bookmark)
            }
            if tagsChanged {
                await bookmarkManager.setTags(tags, for: bookmark)
            }
            if selectionChanged, let selection, let transcript,
               let excerpt = HighlightExcerptBuilder.excerpt(
                   in: selection, cues: transcript.cues, plainText: transcript.plainText
               ) {
                // Store cue-snapped values: the assembled window's own bounds,
                // not the raw handle positions.
                await bookmarkManager.updateTrim(excerpt: excerpt.text, endTime: excerpt.endTime, for: bookmark)
            }

            if titleChanged || tagsChanged || selectionChanged {
                Analytics.track(.highlightEdited, properties: [
                    "source": analyticsSource.analyticsDescription,
                    "trimmed": selectionChanged,
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
