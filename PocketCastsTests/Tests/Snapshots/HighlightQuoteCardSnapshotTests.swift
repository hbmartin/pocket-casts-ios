import SnapshotTesting
import SwiftUI
import XCTest

@testable import podcasts

/// Themed snapshots of the smart-highlight quote share card
/// (plans/AI UX Improvements.md Phase 3).
///
/// The fixture is fully deterministic: a fixed gradient, a file URL that never
/// resolves (the quote layout renders no artwork), and static text. The card
/// paints its own share-image colors, so a single theme baseline suffices.
@MainActor
final class HighlightQuoteCardSnapshotTests: XCTestCase {
    private func info(excerpt: String?) -> ShareImageInfo {
        ShareImageInfo(
            name: "12 Apr 2026",
            title: "Episode 42: The Art of Listening",
            description: "The Deterministic Podcast",
            artwork: URL(string: "file:///nonexistent/artwork.jpg")!,
            gradient: Gradient(colors: [Color(hex: "3240A8"), Color(hex: "101018")]),
            excerpt: excerpt
        )
    }

    func testQuoteCard() {
        assertAppThemedSnapshots(
            of: ShareImageView(
                info: info(excerpt: "The trick isn't listening harder, it's noticing what you were about to dismiss — that's where every good question in this interview came from."),
                style: .quote,
                angle: .constant(0)
            ),
            layout: .fixed(
                width: ShareImageStyle.quote.previewSize.width,
                height: ShareImageStyle.quote.previewSize.height
            ),
            themes: [.light]
        )
    }

    func testQuoteCardWithoutExcerptShowsUnavailableMessage() {
        assertAppThemedSnapshots(
            of: ShareImageView(info: info(excerpt: nil), style: .quote, angle: .constant(0)),
            layout: .fixed(
                width: ShareImageStyle.quote.previewSize.width,
                height: ShareImageStyle.quote.previewSize.height
            ),
            themes: [.light]
        )
    }
}
