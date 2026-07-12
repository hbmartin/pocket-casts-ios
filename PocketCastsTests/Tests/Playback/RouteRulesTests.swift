import XCTest

@testable import podcasts

final class RouteChangeDeciderTests: XCTestCase {
    // MARK: - Disconnect decision table

    func testDisconnectPausesWhenRuleSaysPause() {
        let rule = RouteRule(autoResumeOnConnect: false, pauseOnDisconnect: true)
        XCTAssertEqual(RouteChangeDecider.action(for: .disconnect, rule: rule, isPlaying: true, hasCurrentEpisode: true), .pause)
        XCTAssertEqual(RouteChangeDecider.action(for: .disconnect, rule: rule, isPlaying: false, hasCurrentEpisode: false), .pause)
    }

    func testDisconnectDoesNothingWhenPauseRuleIsOff() {
        let rule = RouteRule(autoResumeOnConnect: false, pauseOnDisconnect: false)
        XCTAssertEqual(RouteChangeDecider.action(for: .disconnect, rule: rule, isPlaying: true, hasCurrentEpisode: true), .noChange)
        XCTAssertEqual(RouteChangeDecider.action(for: .disconnect, rule: rule, isPlaying: false, hasCurrentEpisode: true), .noChange)
    }

    func testDefaultRulePausesOnDisconnect() {
        // Today's hard-wired pause must remain the default for unconfigured routes
        XCTAssertEqual(RouteChangeDecider.action(for: .disconnect, rule: RouteRule(), isPlaying: true, hasCurrentEpisode: true), .pause)
    }

    // MARK: - Connect decision table

    func testConnectResumesOnlyWhenOptedInPausedAndEpisodeLoaded() {
        let optedIn = RouteRule(autoResumeOnConnect: true, pauseOnDisconnect: true)
        XCTAssertEqual(RouteChangeDecider.action(for: .connect, rule: optedIn, isPlaying: false, hasCurrentEpisode: true), .resume)
    }

    func testConnectDoesNothingWhenAlreadyPlaying() {
        let optedIn = RouteRule(autoResumeOnConnect: true, pauseOnDisconnect: true)
        XCTAssertEqual(RouteChangeDecider.action(for: .connect, rule: optedIn, isPlaying: true, hasCurrentEpisode: true), .noChange)
    }

    func testConnectDoesNothingWithoutACurrentEpisode() {
        let optedIn = RouteRule(autoResumeOnConnect: true, pauseOnDisconnect: true)
        XCTAssertEqual(RouteChangeDecider.action(for: .connect, rule: optedIn, isPlaying: false, hasCurrentEpisode: false), .noChange)
    }

    func testConnectDoesNothingByDefault() {
        // The retired dontAutoplayOnRouteChange behavior is now the default: no auto-resume
        XCTAssertEqual(RouteChangeDecider.action(for: .connect, rule: RouteRule(), isPlaying: false, hasCurrentEpisode: true), .noChange)
        XCTAssertEqual(RouteChangeDecider.action(for: .connect, rule: RouteRule(), isPlaying: true, hasCurrentEpisode: true), .noChange)
    }
}

@MainActor
final class RouteRulesStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: RouteRulesStore!
    private let suiteName = "RouteRulesStoreTests"

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = RouteRulesStore(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testIdentityCombinesPortTypeAndName() {
        XCTAssertEqual(RouteRulesStore.identity(portType: "BluetoothA2DPOutput", portName: "Living Room"), "BluetoothA2DPOutput|Living Room")
    }

    func testUnknownRouteGetsDefaultRule() {
        let rule = store.rule(for: "BluetoothA2DPOutput|Unknown")
        XCTAssertFalse(rule.autoResumeOnConnect)
        XCTAssertTrue(rule.pauseOnDisconnect)
    }

    func testRuleRoundTripsThroughUserDefaults() {
        let identity = "BluetoothA2DPOutput|My Headphones"
        store.setRule(RouteRule(autoResumeOnConnect: true, pauseOnDisconnect: false), for: identity)

        // A fresh store instance reading the same defaults sees the persisted rule
        let reloaded = RouteRulesStore(defaults: defaults)
        XCTAssertEqual(reloaded.rule(for: identity), RouteRule(autoResumeOnConnect: true, pauseOnDisconnect: false))
        // Other routes are unaffected
        XCTAssertEqual(reloaded.rule(for: "CarAudioOutput|Car"), RouteRule())
    }

    func testSettingTheDefaultRuleClearsTheStoredEntry() {
        let identity = "BluetoothA2DPOutput|My Headphones"
        store.setRule(RouteRule(autoResumeOnConnect: true, pauseOnDisconnect: true), for: identity)
        store.setRule(RouteRule(), for: identity)

        let reloaded = RouteRulesStore(defaults: defaults)
        XCTAssertEqual(reloaded.rule(for: identity), RouteRule())
    }

    func testNoteSeenRecordsRoutesMostRecentFirst() {
        store.noteSeen(identity: "a|A", displayName: "A", date: Date(timeIntervalSince1970: 100))
        store.noteSeen(identity: "b|B", displayName: "B", date: Date(timeIntervalSince1970: 200))

        let routes = store.recentRoutes
        XCTAssertEqual(routes.map(\.identity), ["b|B", "a|A"])
        XCTAssertEqual(routes.first?.displayName, "B")
    }

    func testNoteSeenUpdatesAnExistingRouteInsteadOfDuplicating() {
        store.noteSeen(identity: "a|A", displayName: "A", date: Date(timeIntervalSince1970: 100))
        store.noteSeen(identity: "b|B", displayName: "B", date: Date(timeIntervalSince1970: 200))
        store.noteSeen(identity: "a|A", displayName: "A renamed", date: Date(timeIntervalSince1970: 300))

        let routes = store.recentRoutes
        XCTAssertEqual(routes.map(\.identity), ["a|A", "b|B"])
        XCTAssertEqual(routes.first?.displayName, "A renamed")
        XCTAssertEqual(routes.first?.lastSeen, Date(timeIntervalSince1970: 300))
    }

    func testRecentRoutesAreCapped() {
        for i in 0..<(RouteRulesStore.maxRecentRoutes + 5) {
            store.noteSeen(identity: "type|Device \(i)", displayName: "Device \(i)", date: Date(timeIntervalSince1970: TimeInterval(i)))
        }

        let routes = store.recentRoutes
        XCTAssertEqual(routes.count, RouteRulesStore.maxRecentRoutes)
        // The oldest entries fell off; the newest is first
        XCTAssertEqual(routes.first?.identity, "type|Device 14")
        XCTAssertFalse(routes.contains { $0.identity == "type|Device 0" })
    }

    func testRecentRoutesRoundTripThroughUserDefaults() {
        store.noteSeen(identity: "a|A", displayName: "A", date: Date(timeIntervalSince1970: 100))

        let reloaded = RouteRulesStore(defaults: defaults)
        XCTAssertEqual(reloaded.recentRoutes.count, 1)
        XCTAssertEqual(reloaded.recentRoutes.first?.identity, "a|A")
        XCTAssertEqual(reloaded.recentRoutes.first?.lastSeen, Date(timeIntervalSince1970: 100))
    }
}
