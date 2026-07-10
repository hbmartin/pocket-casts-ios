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
}

extension Tag {
    @Tag static var integration: Self
    @Tag static var opml: Self
}
