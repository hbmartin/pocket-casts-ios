import Testing
import PocketCastsDataModel
@testable import PocketCastsServer

@Suite("Subscribe-time refresh-source policy")
struct SubscribeRefreshSourcePolicyTests {
    @Test("signed-out subscribe of a server podcast with a feed url flips to localFeed")
    func signedOutSubscribeFlips() {
        #expect(ServerPodcastManager.effectiveRefreshSource(
            requested: .server, subscribe: true, isLoggedIn: false, feedUrlPresent: true
        ) == .localFeed)
    }

    @Test("signed-in subscribes stay on server refresh")
    func signedInStaysServer() {
        #expect(ServerPodcastManager.effectiveRefreshSource(
            requested: .server, subscribe: true, isLoggedIn: true, feedUrlPresent: true
        ) == .server)
    }

    @Test("non-subscribe adds (up next lookups, previews) never flip")
    func nonSubscribeNeverFlips() {
        #expect(ServerPodcastManager.effectiveRefreshSource(
            requested: .server, subscribe: false, isLoggedIn: false, feedUrlPresent: true
        ) == .server)
    }

    @Test("a missing feed url keeps the row on server — localFeed without a url never refreshes")
    func missingFeedUrlStaysServer() {
        #expect(ServerPodcastManager.effectiveRefreshSource(
            requested: .server, subscribe: true, isLoggedIn: false, feedUrlPresent: false
        ) == .server)
    }

    @Test("explicit localFeed requests pass through untouched")
    func explicitLocalFeedUntouched() {
        #expect(ServerPodcastManager.effectiveRefreshSource(
            requested: .localFeed, subscribe: true, isLoggedIn: true, feedUrlPresent: true
        ) == .localFeed)
        #expect(ServerPodcastManager.effectiveRefreshSource(
            requested: .localFeed, subscribe: false, isLoggedIn: false, feedUrlPresent: false
        ) == .localFeed)
    }
}
