import PocketCastsDataModel
import PocketCastsUtils
import SwiftUI

/// Display model for one library-transcript search hit. Built off the main actor
/// by `SearchResultsModel` (title resolution reads the database), then rendered by
/// `TranscriptSearchResultRow`. Snapshot tests construct fixtures directly.
nonisolated struct TranscriptSearchHitDisplay: Hashable, Sendable, Identifiable {
    /// One styled fragment of a snippet. Consecutive runs concatenate back into
    /// the full snippet text; `isHighlighted` marks the FTS-matched terms (the
    /// `<b>`…`</b>` ranges of the raw snippet).
    struct Run: Hashable, Sendable {
        let text: String
        let isHighlighted: Bool
    }

    let episodeUuid: String
    let podcastUuid: String?
    let segmentIndex: Int
    let episodeTitle: String
    let runs: [Run]
    let startTime: TimeInterval
    /// Diarized speaker label for generated-transcript hits; nil for provided ones.
    let speaker: String?
    /// Which corpus indexed the segment. `.generated` times are native to the
    /// local audio; `.provided` times may be on a reference timeline when the
    /// indexed transcript was server-generated. (The app module has its own
    /// `TranscriptSource` enum, hence the qualified name.)
    let source: PocketCastsDataModel.TranscriptSource
    /// How the hit matched (exact keyword, vector similarity, or both).
    /// Analytics only — the row renders every match identically.
    var matchType: TranscriptSearchFusion.MatchType = .exact

    var id: String { "\(episodeUuid)-\(segmentIndex)" }

    /// Resolves hits into display rows, dropping hits whose episode row no longer
    /// exists in the library (the index can outlive an episode; without the row
    /// there is no title to show and no local episode to play).
    static func displays(for hits: [TranscriptSearchHit]) -> [TranscriptSearchHitDisplay] {
        let dataManager = DataManager.sharedManager
        return hits.compactMap { hit in
            guard let episode = dataManager.findBaseEpisode(uuid: hit.episodeUuid) else { return nil }
            return TranscriptSearchHitDisplay(
                episodeUuid: hit.episodeUuid,
                podcastUuid: hit.podcastUuid ?? (episode as? Episode)?.podcastUuid,
                segmentIndex: hit.segmentIndex,
                episodeTitle: episode.displayableTitle(),
                runs: runs(from: hit.snippet),
                startTime: hit.startTime,
                speaker: hit.speaker,
                source: hit.source
            )
        }
    }

    /// Resolves fused (exact + semantic) hits the same way. Semantic snippets
    /// carry no highlight markers, so `runs(from:)` renders them plain.
    static func displays(forFused hits: [TranscriptSearchFusion.FusedHit]) -> [TranscriptSearchHitDisplay] {
        let dataManager = DataManager.sharedManager
        return hits.compactMap { hit in
            guard let episode = dataManager.findBaseEpisode(uuid: hit.episodeUuid) else { return nil }
            return TranscriptSearchHitDisplay(
                episodeUuid: hit.episodeUuid,
                podcastUuid: hit.podcastUuid ?? (episode as? Episode)?.podcastUuid,
                segmentIndex: hit.segmentIndex,
                episodeTitle: episode.displayableTitle(),
                runs: runs(from: hit.snippet),
                startTime: hit.startTime,
                speaker: hit.speaker,
                source: hit.source,
                matchType: hit.matchType
            )
        }
    }

    /// Splits a raw FTS snippet on its `<b>`…`</b>` highlight markers into styled
    /// runs. Degenerate input degrades gracefully: an unterminated start marker
    /// renders the remainder as plain text (markers stripped).
    static func runs(from snippet: String) -> [Run] {
        let startMarker = TranscriptSearchHit.highlightStart
        let endMarker = TranscriptSearchHit.highlightEnd

        var runs = [Run]()
        var remainder = Substring(snippet)
        while let startRange = remainder.range(of: startMarker) {
            guard let endRange = remainder.range(of: endMarker, range: startRange.upperBound ..< remainder.endIndex) else {
                break // unterminated marker: the tail below renders as plain text
            }
            let plain = remainder[..<startRange.lowerBound]
            if !plain.isEmpty {
                runs.append(Run(text: String(plain), isHighlighted: false))
            }
            let highlighted = remainder[startRange.upperBound ..< endRange.lowerBound]
            if !highlighted.isEmpty {
                runs.append(Run(text: String(highlighted), isHighlighted: true))
            }
            remainder = remainder[endRange.upperBound...]
        }
        if !remainder.isEmpty {
            let tail = String(remainder)
                .replacingOccurrences(of: startMarker, with: "")
                .replacingOccurrences(of: endMarker, with: "")
            if !tail.isEmpty {
                runs.append(Run(text: tail, isHighlighted: false))
            }
        }
        return runs
    }
}

/// One library-transcript search result: podcast artwork, episode title, the
/// matched snippet with the search terms bolded, and the match's timestamp.
/// Tap plays the episode from the matched moment; long-press opens episode detail.
struct TranscriptSearchResultRow: View {
    @EnvironmentObject var theme: Theme

    let display: TranscriptSearchHitDisplay
    /// Zero-based rank of the row in the results list, for analytics.
    let position: Int

    var body: some View {
        Button(action: play) {
            HStack(spacing: 12) {
                artwork

                VStack(alignment: .leading, spacing: 2) {
                    Text(display.episodeTitle)
                        .font(style: .footnote, weight: .bold)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                        .lineLimit(1)
                    snippetText
                        .font(style: .subheadline, weight: .regular)
                        .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.caption2)
                        Text(L10n.searchTranscriptsResultAtTime(TimeFormatter.shared.playTimeFormat(time: display.startTime)))
                            .font(style: .caption, weight: .semibold)
                        if let speaker = display.speaker, !speaker.isEmpty {
                            Text(verbatim: "· \(speaker)")
                                .font(style: .caption, weight: .regular)
                                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                                .lineLimit(1)
                        }
                    }
                    .foregroundColor(AppTheme.color(for: .primaryInteractive01, theme: theme))
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture().onEnded { _ in
                openEpisodeDetail()
            }
        )
        .accessibilityElement(children: .combine)
    }

    /// Seeks-and-plays via the canonical deep-link path (loads the episode first
    /// when it isn't the one now playing).
    private func play() {
        let seconds = seekTime
        Analytics.track(.librarySearchTranscriptResultTapped, properties: [
            "position": position,
            "seconds": Int(seconds),
            "match_type": display.matchType.rawValue
        ])
        PlaybackManager.shared.play(episodeUuid: display.episodeUuid, podcastUuid: display.podcastUuid, at: seconds)
    }

    /// Provided-corpus segments indexed from a server-generated transcript carry
    /// reference-timeline times; when the hit's episode is the actively
    /// fingerprinted now-playing episode the time is mapped onto the local
    /// audio. For any other episode no mapping exists at seek time, so the
    /// indexed time is the best available (an inherent limitation — dynamic-ad
    /// offsets can shift the landing spot there).
    private var seekTime: TimeInterval {
        guard display.source == .provided,
              PlaybackManager.shared.isNowPlayingEpisode(episodeUuid: display.episodeUuid),
              case .active = FingerprintTimingManager.shared.state,
              let mapped = FingerprintTimingManager.shared.playbackTime(forReferenceTime: display.startTime) else {
            return display.startTime
        }
        return mapped
    }

    private func openEpisodeDetail() {
        let data = NSMutableDictionary()
        data[NavigationManager.episodeUuidKey] = display.episodeUuid
        if let podcastUuid = display.podcastUuid {
            data[NavigationManager.podcastKey] = podcastUuid
        }
        NavigationManager.sharedManager.navigateTo(NavigationManager.episodePageKey, data: data)
    }

    @ViewBuilder private var artwork: some View {
        Group {
            if let podcastUuid = display.podcastUuid {
                PodcastImage(uuid: podcastUuid)
            } else {
                Rectangle()
                    .fill(AppTheme.color(for: .primaryUi05, theme: theme))
            }
        }
        .frame(width: 56, height: 56)
        .cornerRadius(4)
        .shadow(radius: 3, x: 0, y: 1)
        .allowsHitTesting(false)
    }

    /// Concatenates the snippet runs into one Text, bolding the matched terms.
    private var snippetText: Text {
        display.runs.reduce(Text(verbatim: "")) { text, run in
            text + Text(verbatim: run.text).fontWeight(run.isHighlighted ? .bold : .regular)
        }
    }
}
