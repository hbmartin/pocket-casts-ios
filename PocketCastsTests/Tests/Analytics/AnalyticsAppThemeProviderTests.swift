import PocketCastsUtils
import Synchronization
import XCTest

@testable import podcasts

@MainActor
class AnalyticsAppThemeProviderTests: XCTestCase {
    override func setUp() async throws {
        try FeatureFlagOverrideStore().override(FeatureFlag.appThemePropertiesLogging, withValue: true)
    }

    override func tearDown() async throws {
        try FeatureFlagOverrideStore().override(FeatureFlag.appThemePropertiesLogging, withValue: false)
    }

    func testThemePropertiesAreMergedIntoTrackedEvents() throws {
        let analytics = Analytics()
        analytics.analyticsAppThemeProvider = MockAnalyticsAppThemeProvider()

        let expectation = expectation(description: "adapter should receive the tracked event")
        let adapter = RecordingAdapter(expectation: expectation)
        analytics.register(adapters: [adapter])

        analytics.track(.settingsAppearanceThemeChanged, properties: ["source": "test"])
        waitForExpectations(timeout: 1)

        let tracked = try XCTUnwrap(adapter.recorded.withLock { $0.first })
        XCTAssertEqual(tracked.name, "settings_appearance_theme_changed")
        XCTAssertEqual(tracked.properties["theme"] as? String, "dark")
        XCTAssertEqual(tracked.properties["source"] as? String, "test")
    }
}

private final class RecordingAdapter: AnalyticsAdapter {
    struct TrackedEvent {
        let name: String
        let properties: [String: Sendable]
    }

    let recorded = Mutex<[TrackedEvent]>([])
    private let expectation: XCTestExpectation

    init(expectation: XCTestExpectation) {
        self.expectation = expectation
    }

    func track(name: String, properties: [String: Sendable]) async {
        recorded.withLock { $0.append(TrackedEvent(name: name, properties: properties)) }
        expectation.fulfill()
    }
}

private struct MockAnalyticsAppThemeProvider: AnalyticsAppThemeProviding {
    var appThemeProperties: [String: Sendable] {
        return ["theme": "dark"]
    }
}
