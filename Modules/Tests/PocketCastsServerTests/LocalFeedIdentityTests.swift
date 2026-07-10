import Testing
@testable import PocketCastsServer

@Suite("LocalFeedIdentity")
struct LocalFeedIdentityTests {
    @Test("same seed always produces the same uuid")
    func deterministic() {
        #expect(LocalFeedIdentity.uuid(seed: "https://example.com/feed.xml") == LocalFeedIdentity.uuid(seed: "https://example.com/feed.xml"))
    }

    @Test("distinct seeds produce distinct uuids")
    func distinct() {
        #expect(LocalFeedIdentity.uuid(seed: "https://example.com/a.xml") != LocalFeedIdentity.uuid(seed: "https://example.com/b.xml"))
    }

    @Test("output is a well-formed version-5, RFC 4122-variant uuid")
    func wellFormed() {
        let uuid = LocalFeedIdentity.uuid(seed: "seed")

        let groups = uuid.components(separatedBy: "-")
        #expect(groups.map(\.count) == [8, 4, 4, 4, 12])
        #expect(uuid == uuid.lowercased())

        let versionNibble = groups[2].first
        #expect(versionNibble == "5")

        let variantNibble = groups[3].first
        #expect(["8", "9", "a", "b"].contains(variantNibble.map(String.init) ?? ""))
    }

    @Test("episode identity prefers the feed guid")
    func episodeGuidWins() {
        let fromGuid = LocalFeedIdentity.episodeUuid(guid: "guid-1", enclosureURL: "https://example.com/1.mp3")
        #expect(fromGuid == LocalFeedIdentity.uuid(seed: "guid-1"))
    }

    @Test("episode identity falls back to the enclosure url")
    func episodeEnclosureFallback() {
        let fromEnclosure = LocalFeedIdentity.episodeUuid(guid: "   ", enclosureURL: "https://example.com/1.mp3")
        #expect(fromEnclosure == LocalFeedIdentity.uuid(seed: "https://example.com/1.mp3"))
    }

    @Test("episode identity is nil without any stable seed")
    func episodeNoIdentity() {
        #expect(LocalFeedIdentity.episodeUuid(guid: nil, enclosureURL: nil) == nil)
        #expect(LocalFeedIdentity.episodeUuid(guid: "", enclosureURL: "") == nil)
    }
}
