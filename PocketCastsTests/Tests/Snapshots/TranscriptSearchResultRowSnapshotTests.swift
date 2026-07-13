import SnapshotTesting
import SwiftUI
import XCTest

@testable import podcasts

/// Themed snapshot coverage for the library transcript search result row
/// (plans/AI UX Improvements.md Phase 4). The fixture display model is fully
/// deterministic: a nil podcastUuid renders the placeholder artwork (nothing
/// loads from the network or database).
@MainActor
final class TranscriptSearchResultRowSnapshotTests: XCTestCase {
    private func display(runs: [TranscriptSearchHitDisplay.Run], startTime: TimeInterval = 754, speaker: String? = nil) -> TranscriptSearchHitDisplay {
        TranscriptSearchHitDisplay(
            episodeUuid: "fixture-episode",
            podcastUuid: nil,
            segmentIndex: 3,
            episodeTitle: "142: The Quiet Art of Shipping",
            runs: runs,
            startTime: startTime,
            speaker: speaker
        )
    }

    func testRowWithHighlightedSnippet() {
        assertAppThemedSnapshots(
            of: TranscriptSearchResultRow(
                display: display(runs: [
                    .init(text: "…and that is why ", isHighlighted: false),
                    .init(text: "shipping", isHighlighted: true),
                    .init(text: " small beats planning big, every single time…", isHighlighted: false)
                ]),
                position: 0
            )
            .frame(width: 390)
            .background(Color(UIColor.systemBackground)),
            layout: .fixed(width: 390, height: 96)
        )
    }

    func testRowWithSpeakerLabelFromGeneratedTranscript() {
        assertAppThemedSnapshots(
            of: TranscriptSearchResultRow(
                display: display(runs: [
                    .init(text: "…we should talk about the ", isHighlighted: false),
                    .init(text: "roadmap", isHighlighted: true),
                    .init(text: " before the next release…", isHighlighted: false)
                ], speaker: "Speaker 2"),
                position: 1
            )
            .frame(width: 390)
            .background(Color(UIColor.systemBackground)),
            layout: .fixed(width: 390, height: 96)
        )
    }

    func testRowWithLongSnippetClampsToThreeLines() {
        assertAppThemedSnapshots(
            of: TranscriptSearchResultRow(
                display: display(runs: [
                    .init(text: "…the release train left the station before the ", isHighlighted: false),
                    .init(text: "transcript", isHighlighted: true),
                    .init(text: " tooling was ready, so we spent a very long week rebuilding the indexer from scratch while the beta users kept filing the same bug over and over again…", isHighlighted: false)
                ], startTime: 3673),
                position: 2
            )
            .frame(width: 390)
            .background(Color(UIColor.systemBackground)),
            layout: .fixed(width: 390, height: 120)
        )
    }
}
