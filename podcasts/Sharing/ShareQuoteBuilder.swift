import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Resolves the transcript quote for a share option: the sentence(s) spoken at
/// the shared timestamp (or across the shared clip), for the share text and the
/// link's `q` parameter. Best-effort and read-only — nil whenever there is no
/// transcript or nothing was said in the window, in which case the share is
/// byte-identical to what it was before quotes existed.
nonisolated enum ShareQuoteBuilder {

    /// Longest quote embedded in a share URL; longer text truncates at a word
    /// boundary. The share text carries the same truncated form so the two never
    /// disagree.
    static let maxURLQuoteLength = 200

    /// The quote for a share option, resolved from the stored highlight excerpt
    /// (synchronous) or the episode transcript (loaded off-main).
    @MainActor
    static func quote(for option: SharingModal.Option) async -> String? {
        switch option {
        case .episode, .podcast:
            return nil
        case .highlight(_, let bookmark):
            // Highlights already store their excerpt; no transcript load needed.
            return bookmark.excerpt.map(HighlightExcerptBuilder.normalizedWhitespace)
        case .currentPosition(let episode, let time), .bookmark(let episode, let time), .clip(let episode, let time):
            return await excerptText(
                episode: episode,
                around: time,
                leading: HighlightExcerptBuilder.leadingWindow,
                trailing: HighlightExcerptBuilder.trailingWindow
            )
        case .clipShare(let episode, let clipTime, _):
            // The clip window itself is the quote span.
            return await excerptText(
                episode: episode,
                around: clipTime.start,
                leading: 0,
                trailing: max(0, clipTime.end - clipTime.start)
            )
        }
    }

    /// Word-boundary truncation for URL embedding (grapheme-safe: operates on
    /// `Character`s, never splitting a cluster).
    static func urlQuote(_ text: String) -> String {
        let normalized = HighlightExcerptBuilder.normalizedWhitespace(text)
        guard normalized.count > maxURLQuoteLength else { return normalized }

        let cut = normalized.prefix(maxURLQuoteLength)
        if let lastSpace = cut.lastIndex(of: " ") {
            return String(cut[..<lastSpace])
        }
        return String(cut)
    }

    /// Percent-encodes a quote for query-value position. The allowed set is
    /// `.urlQueryAllowed` minus `&+=?` so the value can never split the query or
    /// read back as a space.
    static func percentEncodedURLQuote(_ text: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    // MARK: - Transcript excerpt loading

    /// Mirrors `HighlightEnricher.buildEnrichment`'s load path: capture the
    /// fingerprint-mapping gate on the main actor, then do transcript download +
    /// cue-window work detached. We only need the text (no end-time write-back),
    /// so the mapped-back-time bookkeeping the enricher does has no counterpart.
    @MainActor
    private static func excerptText(
        episode: Episode,
        around time: TimeInterval,
        leading: TimeInterval,
        trailing: TimeInterval
    ) async -> String? {
        // The fingerprint mapping only ever tracks the currently playing episode.
        let allowFingerprintMapping: Bool = {
            guard PlaybackManager.shared.currentEpisode()?.uuid == episode.uuid,
                  case .active = FingerprintTimingManager.shared.state else {
                return false
            }
            return true
        }()
        let episodeUuid = episode.uuid
        let podcastUuid = episode.podcastUuid

        return await Task.detached(priority: .userInitiated) {
            await loadExcerptText(
                episodeUuid: episodeUuid,
                podcastUuid: podcastUuid,
                around: time,
                leading: leading,
                trailing: trailing,
                allowFingerprintMapping: allowFingerprintMapping
            )
        }.value
    }

    private static func loadExcerptText(
        episodeUuid: String,
        podcastUuid: String,
        around time: TimeInterval,
        leading: TimeInterval,
        trailing: TimeInterval,
        allowFingerprintMapping: Bool
    ) async -> String? {
        let transcriptManager = TranscriptManager(episodeUUID: episodeUuid, podcastUUID: podcastUuid)
        guard let transcript = try? await transcriptManager.loadTranscript(),
              !transcript.cues.isEmpty else {
            return nil
        }

        // Server-generated transcripts are timed against reference audio; local
        // and provided transcripts align natively (same rule as the enricher).
        let mappingApplies = allowFingerprintMapping
            && transcriptManager.isDisplayingGeneratedTranscript
            && !transcriptManager.isDisplayingLocalTranscription

        var anchor = time
        if mappingApplies,
           let mapped = FingerprintTimingManager.shared.referenceTime(forPlaybackTime: time, episodeUuid: episodeUuid) {
            anchor = mapped
        }

        return HighlightExcerptBuilder.excerpt(
            around: anchor,
            cues: transcript.cues,
            plainText: transcript.plainText,
            leading: leading,
            trailing: trailing
        )?.text
    }
}

extension SharingModal.Option {
    /// Stable identity of the inputs `ShareQuoteBuilder.quote(for:)` reads, for
    /// SwiftUI task restarts (`SharingModal.Option` itself isn't Equatable) —
    /// e.g. a clip trimmed via Edit → Next changes the clipShare window and
    /// must re-resolve its quote.
    var quoteResolutionKey: String {
        switch self {
        case .episode(let episode):
            return "episode:\(episode.uuid)"
        case .podcast(let podcast):
            return "podcast:\(podcast.uuid)"
        case .currentPosition(let episode, let time):
            return "currentPosition:\(episode.uuid):\(time)"
        case .bookmark(let episode, let time):
            return "bookmark:\(episode.uuid):\(time)"
        case .highlight(let episode, let bookmark):
            return "highlight:\(episode.uuid):\(bookmark.uuid)"
        case .clip(let episode, let time):
            return "clip:\(episode.uuid):\(time)"
        case .clipShare(let episode, let clipTime, _):
            return "clipShare:\(episode.uuid):\(clipTime.start)-\(clipTime.end)"
        }
    }
}
