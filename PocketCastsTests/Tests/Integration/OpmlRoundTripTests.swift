import Foundation
@testable import PocketCastsDataModel
import Testing
@testable import podcasts

@Suite("OPML round trip", .tags(.integration, .opml))
struct OpmlRoundTripTests {
    @Test("Subscribed podcasts export and parse without losing feed URLs")
    func subscribedPodcastsRoundTrip() throws {
        let sandbox = try IntegrationTestSandbox()
        defer { try? sandbox.cleanUp() }

        let expectedFeeds = [
            "podcast-one": "https://example.test/one.xml?source=library&format=rss",
            "podcast-two": "https://example.test/two.xml"
        ]

        var first = Podcast()
        first.addedDate = Date(timeIntervalSince1970: 1_700_000_000)
        first.title = "Science & Things"
        first.uuid = "podcast-one"
        first.subscribed = 1
        sandbox.dataManager.save(podcast: first)

        var second = Podcast()
        second.addedDate = Date(timeIntervalSince1970: 1_700_000_100)
        second.title = "Quotes <Explained>"
        second.uuid = "podcast-two"
        second.subscribed = 1
        sandbox.dataManager.save(podcast: second)

        let feeds = sandbox.dataManager.allPodcasts(includeUnsubscribed: false).map {
            OpmlFeed(title: $0.title ?? "", url: expectedFeeds[$0.uuid] ?? "")
        }
        let xml = OpmlDocument.xmlString(feeds: feeds)
        let importedURLs = try OpmlDocument.feedURLs(from: Data(xml.utf8))

        #expect(Set(importedURLs) == Set(expectedFeeds.values))
        #expect(importedURLs.count == expectedFeeds.count)
    }

    @Test("Offline export builds feeds from local rows and skips podcasts without a feed URL")
    func offlineExportFromLocalRows() throws {
        let sandbox = try IntegrationTestSandbox()
        defer { try? sandbox.cleanUp() }

        var withURL = Podcast()
        withURL.addedDate = Date(timeIntervalSince1970: 1_700_000_000)
        withURL.title = "Has Feed URL"
        withURL.uuid = "podcast-with-url"
        withURL.podcastUrl = "https://example.test/with.xml"
        withURL.subscribed = 1
        sandbox.dataManager.save(podcast: withURL)

        // legacy server-sourced rows can predate podcastUrl storage
        var withoutURL = Podcast()
        withoutURL.addedDate = Date(timeIntervalSince1970: 1_700_000_100)
        withoutURL.title = "Legacy Row"
        withoutURL.uuid = "podcast-without-url"
        withoutURL.subscribed = 1
        sandbox.dataManager.save(podcast: withoutURL)

        // the exact export mapping ImportExportViewController.startExport uses
        let feeds = sandbox.dataManager.allPodcasts(includeUnsubscribed: false)
            .compactMap { podcast -> OpmlFeed? in
                guard let url = podcast.podcastUrl, !url.isEmpty else { return nil }
                return OpmlFeed(title: podcast.title ?? "", url: url)
            }

        let importedURLs = try OpmlDocument.feedURLs(from: Data(OpmlDocument.xmlString(feeds: feeds).utf8))
        #expect(importedURLs == ["https://example.test/with.xml"])
    }

    @Test("Export sanitization strips credentials and fails closed")
    func exportURLSanitization() {
        #expect(ImportExportViewController.strippingCredentials(
            from: "https://user:password@example.test/feed.xml"
        ) == "https://example.test/feed.xml")
        #expect(ImportExportViewController.strippingCredentials(from: "https://[::1/feed.xml") == nil)
    }
}

extension Tag {
    @Tag static var integration: Self
    @Tag static var opml: Self
}
