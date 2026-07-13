import PocketCastsDataModel
import SnapshotTesting
import SwiftUI
import XCTest

@testable import podcasts

/// Themed snapshot coverage for the people-credits card on the episode detail
/// screen (plans/AI UX Improvements.md Phase 6). Fixtures use the no-tracking
/// view-model initializer and carry no image URLs, so every avatar renders the
/// deterministic initials fallback — nothing loads, tracks, or hits the
/// network during rendering.
@MainActor
final class EpisodeCreditsCardSnapshotTests: XCTestCase {
    func testCreditsCard() {
        assertAppThemedSnapshots(
            of: EpisodeCreditsView(
                viewModel: EpisodeCreditsViewModel(fixturePersons: [
                    Episode.Metadata.Person(name: "Jane Host", role: "host", group: "cast"),
                    Episode.Metadata.Person(name: "Gina Guest", role: "guest"),
                    Episode.Metadata.Person(name: "Plain Name")
                ])
            ),
            layout: .fixed(width: 390, height: 160)
        )
    }

    func testCreditsCardSinglePerson() {
        assertAppThemedSnapshots(
            of: EpisodeCreditsView(
                viewModel: EpisodeCreditsViewModel(fixturePersons: [
                    Episode.Metadata.Person(name: "Solo Host", role: "host")
                ])
            ),
            layout: .fixed(width: 390, height: 160)
        )
    }
}
