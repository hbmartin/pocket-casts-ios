import Foundation
import Testing
import PocketCastsDataModel
@testable import PocketCastsServer

@Suite("LocalFeedEpisodeMatcher")
struct LocalFeedEpisodeMatcherTests {
    private func item(guid: String? = nil, title: String? = nil, enclosure: String? = nil, published: Date? = nil) -> ParsedFeedItem {
        var item = ParsedFeedItem()
        item.guid = guid
        item.title = title
        item.enclosureURL = enclosure
        item.publishedDate = published
        return item
    }

    private func episode(uuid: String, title: String? = nil, downloadUrl: String? = nil, published: Date? = nil) -> Episode {
        var episode = Episode()
        episode.uuid = uuid
        episode.title = title
        episode.downloadUrl = downloadUrl
        episode.publishedDate = published
        episode.addedDate = Date(timeIntervalSince1970: 0)
        return episode
    }

    @Test("hash uuid already in the database wins first")
    func hashUuidMatch() {
        let hashUuid = LocalFeedIdentity.uuid(seed: "guid-1")
        let matches = LocalFeedEpisodeMatcher.match(
            items: [item(guid: "guid-1", enclosure: "https://example.com/1.mp3")],
            existing: [episode(uuid: hashUuid)]
        )
        #expect(matches == [.existing(uuid: hashUuid)])
    }

    @Test("server-canonical catalog matches by exact enclosure url")
    func enclosureMatch() {
        let matches = LocalFeedEpisodeMatcher.match(
            items: [item(guid: "guid-1", enclosure: "https://example.com/1.mp3")],
            existing: [episode(uuid: "server-uuid-1", downloadUrl: "https://example.com/1.mp3")]
        )
        #expect(matches == [.existing(uuid: "server-uuid-1")])
    }

    @Test("changed enclosure with same title and published day is suppressed by the fallback")
    func titleAndDateFallback() {
        let published = Date(timeIntervalSince1970: 1_700_000_000)
        let matches = LocalFeedEpisodeMatcher.match(
            items: [item(guid: "guid-1", title: "  Episode ONE  ", enclosure: "https://cdn2.example.com/1.mp3", published: published)],
            existing: [episode(uuid: "server-uuid-1", title: "episode one", downloadUrl: "https://cdn1.example.com/1.mp3", published: published.addingTimeInterval(3600))]
        )
        #expect(matches == [.existing(uuid: "server-uuid-1")])
    }

    @Test("title fallback requires the same UTC day")
    func titleFallbackDayBoundary() {
        let published = Date(timeIntervalSince1970: 1_700_000_000)
        let matches = LocalFeedEpisodeMatcher.match(
            items: [item(guid: "guid-1", title: "Episode One", enclosure: "https://cdn2.example.com/1.mp3", published: published)],
            existing: [episode(uuid: "server-uuid-1", title: "Episode One", downloadUrl: "https://cdn1.example.com/1.mp3", published: published.addingTimeInterval(60 * 60 * 30))]
        )
        #expect(matches == [.new(hashUuid: LocalFeedIdentity.uuid(seed: "guid-1"))])
    }

    @Test("same-title same-day episode with a distinct guid is NOT collapsed onto its sibling")
    func distinctGuidSameTitleSameDayIngests() {
        // Daily-brief shape: episode one already ingested under its hash uuid;
        // episode two shares the title and UTC day but is a different item.
        let published = Date(timeIntervalSince1970: 1_700_000_000)
        let storedUuid = LocalFeedIdentity.uuid(seed: "guid-1")
        let matches = LocalFeedEpisodeMatcher.match(
            items: [
                item(guid: "guid-1", title: "Live Update", enclosure: "https://example.com/1.mp3", published: published),
                item(guid: "guid-2", title: "Live Update", enclosure: "https://example.com/2.mp3", published: published.addingTimeInterval(3600))
            ],
            existing: [episode(uuid: storedUuid, title: "Live Update", downloadUrl: "https://example.com/1.mp3", published: published)]
        )
        #expect(matches == [
            .existing(uuid: storedUuid),
            .new(hashUuid: LocalFeedIdentity.uuid(seed: "guid-2"))
        ])
    }

    @Test("the fallback claims a stored episode at most once per refresh")
    func fallbackClaimsAtMostOnce() {
        // Both items miss exactly (new guids, new enclosures) and share the
        // stored episode's title+day: only one may merge onto it.
        let published = Date(timeIntervalSince1970: 1_700_000_000)
        let matches = LocalFeedEpisodeMatcher.match(
            items: [
                item(guid: "guid-a", title: "Live Update", enclosure: "https://cdn2.example.com/a.mp3", published: published),
                item(guid: "guid-b", title: "Live Update", enclosure: "https://cdn2.example.com/b.mp3", published: published.addingTimeInterval(3600))
            ],
            existing: [episode(uuid: "server-uuid-1", title: "Live Update", downloadUrl: "https://cdn1.example.com/1.mp3", published: published)]
        )
        #expect(matches == [
            .existing(uuid: "server-uuid-1"),
            .new(hashUuid: LocalFeedIdentity.uuid(seed: "guid-b"))
        ])
    }

    @Test("genuinely new item mints exactly its deterministic hash uuid")
    func newItem() {
        let matches = LocalFeedEpisodeMatcher.match(
            items: [item(guid: "guid-new", enclosure: "https://example.com/new.mp3")],
            existing: [episode(uuid: "server-uuid-1", downloadUrl: "https://example.com/old.mp3")]
        )
        #expect(matches == [.new(hashUuid: LocalFeedIdentity.uuid(seed: "guid-new"))])
    }

    @Test("item with no derivable identity is skipped")
    func noIdentity() {
        let matches = LocalFeedEpisodeMatcher.match(
            items: [item(title: "Only a title")],
            existing: []
        )
        #expect(matches == [nil])
    }

    @Test("guid-less feed matches its own prior hash uuids by enclosure seed")
    func guidlessFeedIdempotent() {
        let hashUuid = LocalFeedIdentity.uuid(seed: "https://example.com/1.mp3")
        let matches = LocalFeedEpisodeMatcher.match(
            items: [item(enclosure: "https://example.com/1.mp3")],
            existing: [episode(uuid: hashUuid, downloadUrl: "https://example.com/1.mp3")]
        )
        #expect(matches == [.existing(uuid: hashUuid)])
    }

    @Test("matching is pure: same inputs, same outputs, input order preserved")
    func pureAndOrdered() {
        let items = [
            item(guid: "a", enclosure: "https://example.com/a.mp3"),
            item(title: "no identity"),
            item(guid: "b", enclosure: "https://example.com/b.mp3")
        ]
        let existing = [episode(uuid: "server-b", downloadUrl: "https://example.com/b.mp3")]

        let first = LocalFeedEpisodeMatcher.match(items: items, existing: existing)
        let second = LocalFeedEpisodeMatcher.match(items: items, existing: existing)

        #expect(first == second)
        #expect(first == [
            .new(hashUuid: LocalFeedIdentity.uuid(seed: "a")),
            nil,
            .existing(uuid: "server-b")
        ])
    }
}

@Suite("LocalFeedRefreshProvider resolution")
struct LocalFeedRefreshProviderResolveTests {
    private func feed(items: [ParsedFeedItem]) -> ParsedFeed {
        var feed = ParsedFeed()
        feed.items = items
        return feed
    }

    private func item(guid: String, enclosure: String, title: String? = nil) -> ParsedFeedItem {
        var item = ParsedFeedItem()
        item.guid = guid
        item.enclosureURL = enclosure
        item.title = title
        return item
    }

    private func episode(uuid: String, downloadUrl: String) -> Episode {
        var episode = Episode()
        episode.uuid = uuid
        episode.downloadUrl = downloadUrl
        episode.addedDate = Date(timeIntervalSince1970: 0)
        return episode
    }

    @Test("cache-seeded catalog + full feed parse produces zero new episodes")
    func fullySeededCatalogYieldsNothingNew() {
        let items = (1...5).map { item(guid: "guid-\($0)", enclosure: "https://example.com/\($0).mp3") }
        let existing = (1...5).map { episode(uuid: "server-\($0)", downloadUrl: "https://example.com/\($0).mp3") }

        let resolution = LocalFeedRefreshProvider.resolve(feed: feed(items: items), existing: existing)

        #expect(resolution.newEpisodes.isEmpty)
        #expect(resolution.uuidOverrides.count == 5)
        #expect(resolution.uuidOverrides[LocalFeedIdentity.uuid(seed: "guid-3")] == "server-3")
    }

    @Test("new item yields exactly one refresh episode; second resolve is idempotent")
    func newItemOnceThenIdempotent() {
        let items = [
            item(guid: "guid-old", enclosure: "https://example.com/old.mp3"),
            item(guid: "guid-new", enclosure: "https://example.com/new.mp3")
        ]
        let existing = [episode(uuid: "server-old", downloadUrl: "https://example.com/old.mp3")]

        let first = LocalFeedRefreshProvider.resolve(feed: feed(items: items), existing: existing)
        #expect(first.newEpisodes.map(\.uuid) == [LocalFeedIdentity.uuid(seed: "guid-new")])

        // Simulate the new episode having been ingested under its hash uuid.
        let afterIngest = existing + [episode(uuid: LocalFeedIdentity.uuid(seed: "guid-new"), downloadUrl: "https://example.com/new.mp3")]
        let second = LocalFeedRefreshProvider.resolve(feed: feed(items: items), existing: afterIngest)
        #expect(second.newEpisodes.isEmpty)
    }

    @Test("pure-local podcasts produce no overrides (identity mapping)")
    func pureLocalNoOverrides() {
        let hashUuid = LocalFeedIdentity.uuid(seed: "guid-1")
        let items = [item(guid: "guid-1", enclosure: "https://example.com/1.mp3")]
        let existing = [episode(uuid: hashUuid, downloadUrl: "https://example.com/1.mp3")]

        let resolution = LocalFeedRefreshProvider.resolve(feed: feed(items: items), existing: existing)

        #expect(resolution.newEpisodes.isEmpty)
        #expect(resolution.uuidOverrides.isEmpty)
    }
}

@Suite("LocalFeedShowInfo uuid overrides")
struct LocalFeedShowInfoOverrideTests {
    @Test("seeded show-info keys matched items under their stored uuids")
    func overridesRekeyEpisodes() throws {
        var item = ParsedFeedItem()
        item.guid = "guid-1"
        item.enclosureURL = "https://example.com/1.mp3"
        item.itemDescriptionHTML = "<p>Notes</p>"
        var feed = ParsedFeed()
        feed.items = [item]

        let hashUuid = LocalFeedIdentity.uuid(seed: "guid-1")
        let data = try #require(LocalFeedShowInfo.data(
            from: feed,
            podcastUuid: "podcast-uuid",
            resolvedUuidOverrides: [hashUuid: "server-uuid-1"]
        ))

        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let podcast = try #require(json["podcast"] as? [String: Any])
        let episodes = try #require(podcast["episodes"] as? [[String: Any]])
        #expect(episodes.count == 1)
        #expect(episodes.first?["uuid"] as? String == "server-uuid-1")
        #expect(episodes.first?["show_notes"] as? String == "<p>Notes</p>")
    }

    @Test("without overrides the hash uuid keys the entry (pure-local unchanged)")
    func identityMappingByDefault() throws {
        var item = ParsedFeedItem()
        item.guid = "guid-1"
        item.enclosureURL = "https://example.com/1.mp3"
        var feed = ParsedFeed()
        feed.items = [item]

        let data = try #require(LocalFeedShowInfo.data(from: feed, podcastUuid: "podcast-uuid"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let podcast = try #require(json["podcast"] as? [String: Any])
        let episodes = try #require(podcast["episodes"] as? [[String: Any]])
        #expect(episodes.first?["uuid"] as? String == LocalFeedIdentity.uuid(seed: "guid-1"))
    }
}

@Suite("LocalFeedShowInfo persons")
struct LocalFeedShowInfoPersonsTests {
    private func firstEpisode(from feed: ParsedFeed) throws -> [String: Any] {
        let data = try #require(LocalFeedShowInfo.data(from: feed, podcastUuid: "podcast-uuid"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let podcast = try #require(json["podcast"] as? [String: Any])
        let episodes = try #require(podcast["episodes"] as? [[String: Any]])
        return try #require(episodes.first)
    }

    private func makeItem() -> ParsedFeedItem {
        var item = ParsedFeedItem()
        item.guid = "guid-1"
        item.enclosureURL = "https://example.com/1.mp3"
        return item
    }

    @Test("item-level persons are emitted with only the attributes they carry")
    func itemPersons() throws {
        var item = makeItem()
        item.persons = [
            ParsedFeedPerson(name: "Gina Guest", role: "guest", group: "cast", img: "https://example.com/g.jpg", href: "https://example.com/g"),
            ParsedFeedPerson(name: "Plain Name")
        ]
        var feed = ParsedFeed()
        feed.persons = [ParsedFeedPerson(name: "Channel Host", role: "host")]
        feed.items = [item]

        let episode = try firstEpisode(from: feed)
        let persons = try #require(episode["persons"] as? [[String: Any]])
        #expect(persons.count == 2)

        let gina = try #require(persons.first)
        #expect(gina["name"] as? String == "Gina Guest")
        #expect(gina["role"] as? String == "guest")
        #expect(gina["group"] as? String == "cast")
        #expect(gina["img"] as? String == "https://example.com/g.jpg")
        #expect(gina["href"] as? String == "https://example.com/g")

        let plain = try #require(persons.last)
        #expect(plain["name"] as? String == "Plain Name")
        #expect(plain.count == 1, "optional attributes must be omitted, not emitted as null")
    }

    @Test("items without persons inherit the channel-level credits")
    func channelFallback() throws {
        var feed = ParsedFeed()
        feed.persons = [ParsedFeedPerson(name: "Channel Host", role: "host")]
        feed.items = [makeItem()]

        let episode = try firstEpisode(from: feed)
        let persons = try #require(episode["persons"] as? [[String: Any]])
        #expect(persons.count == 1)
        #expect(persons.first?["name"] as? String == "Channel Host")
        #expect(persons.first?["role"] as? String == "host")
    }

    @Test("no persons key when neither the item nor the channel declares credits")
    func omittedWhenEmpty() throws {
        var feed = ParsedFeed()
        feed.items = [makeItem()]

        let episode = try firstEpisode(from: feed)
        #expect(episode["persons"] == nil)
    }
}
