import XCTest
@testable import podcasts
import PocketCastsDataModel

/// Tests for the pure, record-derived computed properties of PodcastHeaderViewModel
/// (PodcastHeaderModel.swift). Constructed with a plain `Podcast` and no delegate; only properties that
/// read the podcast (not delegate/sync/UI) are exercised. `@MainActor` because the view model is an
/// `ObservableObject` that registers observers in `init`.
@MainActor
final class PodcastHeaderViewModelTests: XCTestCase {

    private func makeViewModel(configure: (inout Podcast) -> Void) -> PodcastHeaderViewModel {
        var podcast = Podcast()
        configure(&podcast)
        return PodcastHeaderViewModel(podcast: podcast)
    }

    func testFirstCategory_usesFirstLineLowercased() {
        let vm = makeViewModel { $0.podcastCategory = "Technology\nGadgets" }
        XCTAssertEqual(vm.firstCategory, "technology")
    }

    func testFirstCategory_emptyWhenNoCategory() {
        let vm = makeViewModel { $0.podcastCategory = nil }
        XCTAssertEqual(vm.firstCategory, "")
    }

    func testDisplayAuthor_returnsAuthorOrNil() {
        XCTAssertEqual(makeViewModel { $0.author = "Jane Doe" }.displayAuthor, "Jane Doe")
        XCTAssertNil(makeViewModel { $0.author = nil }.displayAuthor)
    }

    func testDisplayWebsite_stripsWWWAndReturnsHost() {
        XCTAssertEqual(makeViewModel { $0.podcastUrl = "https://www.example.com/feed" }.displayWebsite, "example.com")
        XCTAssertEqual(makeViewModel { $0.podcastUrl = "https://foo.org/rss" }.displayWebsite, "foo.org")
    }

    func testDisplayWebsite_nilWhenNoUsableURL() {
        XCTAssertNil(makeViewModel { $0.podcastUrl = nil }.displayWebsite)
    }

    func testDisplayFrequency_wrapsTranslatedFrequency() {
        let vm = makeViewModel { $0.episodeFrequency = "daily" }
        XCTAssertEqual(vm.displayFrequency, L10n.paidPodcastReleaseFrequencyFormat(L10n.releaseFrequencyDaily.localizedCapitalized))
    }

    func testDisplayFrequency_nilWhenUnknown() {
        XCTAssertNil(makeViewModel { $0.episodeFrequency = "unknown" }.displayFrequency)
    }

    func testHtmlDescription_prefersHTMLThenPlainThenEmpty() {
        XCTAssertEqual(makeViewModel { $0.podcastHTMLDescription = "<p>hi</p>"; $0.podcastDescription = "hi" }.htmlDescription, "<p>hi</p>")
        XCTAssertEqual(makeViewModel { $0.podcastHTMLDescription = nil; $0.podcastDescription = "plain" }.htmlDescription, "plain")
        XCTAssertEqual(makeViewModel { $0.podcastHTMLDescription = nil; $0.podcastDescription = nil }.htmlDescription, "")
    }
}
