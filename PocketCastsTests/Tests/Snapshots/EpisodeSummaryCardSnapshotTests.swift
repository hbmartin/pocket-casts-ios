import SnapshotTesting
import SwiftUI
import XCTest

@testable import podcasts

/// Themed snapshot coverage for the AI episode summary card
/// (plans/AI UX Improvements.md Phase 2). All states use the fixture view
/// model, so nothing loads, tracks, or touches playback during rendering.
@MainActor
final class EpisodeSummaryCardSnapshotTests: XCTestCase {
    private let shortSummary = "A tight episode about why writing beats meetings for small teams, and what changed after the big rewrite."

    private let longSummary = """
    A deep dive into how small teams ship fast. The hosts break down why fewer \
    meetings and a stronger written culture beat raising headcount, how the \
    rewrite at 45:10 only worked because scope was frozen first, and what the \
    on-call rotation looked like once the pager finally went quiet. They close \
    with listener questions about hiring, estimation, and the true cost of a \
    rewrite that nobody asked for.
    """

    func testSummaryCardWithTakeaways() {
        assertAppThemedSnapshots(
            of: EpisodeSummaryCardView(
                viewModel: EpisodeSummaryViewModel(
                    fixtureSummary: shortSummary,
                    takeaways: [
                        Takeaway(text: "Small teams move faster when writing replaces meetings.", startTime: 150),
                        Takeaway(text: "The rewrite only worked because scope was frozen first.", startTime: 2710)
                    ],
                    layer: .foundationModels
                )
            ),
            layout: .fixed(width: 390, height: 320)
        )
    }

    func testSummaryCardKeyMomentsFallback() {
        assertAppThemedSnapshots(
            of: EpisodeSummaryCardView(
                viewModel: EpisodeSummaryViewModel(
                    fixtureSummary: shortSummary,
                    takeaways: [
                        Takeaway(text: "Introduction", startTime: 0),
                        Takeaway(text: "Interview", startTime: 620),
                        Takeaway(text: "Listener questions", startTime: 3753)
                    ],
                    layer: .generatedChapters
                )
            ),
            layout: .fixed(width: 390, height: 360)
        )
    }

    func testSummaryCardSummaryOnlyCollapsed() {
        assertAppThemedSnapshots(
            of: EpisodeSummaryCardView(
                viewModel: EpisodeSummaryViewModel(
                    fixtureSummary: longSummary,
                    takeaways: [],
                    layer: .summaryOnly
                )
            ),
            layout: .fixed(width: 390, height: 240)
        )
    }

    func testSummaryCardSummaryOnlyExpanded() {
        assertAppThemedSnapshots(
            of: EpisodeSummaryCardView(
                viewModel: EpisodeSummaryViewModel(
                    fixtureSummary: longSummary,
                    takeaways: [],
                    layer: .summaryOnly,
                    isExpanded: true
                )
            ),
            layout: .fixed(width: 390, height: 340)
        )
    }
}
