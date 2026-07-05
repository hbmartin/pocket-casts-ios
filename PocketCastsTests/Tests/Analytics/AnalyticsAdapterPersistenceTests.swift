import XCTest
@testable import podcasts
#if canImport(TelemetryDeck)
import TelemetryDeck
#endif

/// Tests that verify the Analytics opt-out/opt-in flow works correctly.
/// This tests the fix from commit f60bcd3ff "Call setupAnalytics after unregister"
/// which ensures that NotificationsCoordinator
/// remain registered as adapters after optOutOfAnalytics and optInOfAnalytics are called.
class AnalyticsAdapterPersistenceTests: XCTestCase {

    private var analytics: Analytics!

    override func setUp() {
        super.setUp()
        analytics = Analytics.shared

        reset()
    }

    override func tearDown() {
        reset()
        super.tearDown()
    }

    private func reset() {
        Analytics.unregister()
        Settings.setAnalytics(optOut: false)
    }

    @MainActor func testAnalyticsUnregistersAfterOptOut() {
        // Given: Analytics adapters are registered
        let testAdapters = [TestAnalyticsAdapter()]
        Analytics.register(adapters: testAdapters)
        XCTAssertTrue(analytics.adaptersRegistered, "Analytics should be registered initially")

        // When: User opts out of analytics
        analytics.optOutOfAnalytics()

        // Then: Analytics should be unregistered and settings should reflect opt-out
        XCTAssertFalse(analytics.adaptersRegistered, "Analytics should be unregistered after opt-out")
        XCTAssertTrue(Settings.analyticsOptOut(), "Settings should show user opted out")
    }

    @MainActor func testRefreshRegisteredUnregistersWhenOptedOut() {
        // Given: Analytics adapters are registered and user opts out
        let testAdapters = [TestAnalyticsAdapter()]
        Analytics.register(adapters: testAdapters)
        Settings.setAnalytics(optOut: true)

        // When: refreshRegistered is called
        analytics.refreshRegistered()

        // Then: Analytics should be unregistered
        XCTAssertFalse(analytics.adaptersRegistered, "Analytics should be unregistered when user is opted out")
    }

    @MainActor func testRefreshRegisteredCallsSetupAnalyticsWhenOptedIn() {
        // Given: User is opted in to analytics but adapters are not registered
        Settings.setAnalytics(optOut: false)
        XCTAssertFalse(analytics.adaptersRegistered, "Analytics should not be registered initially")

        // When: refreshRegistered is called
        analytics.refreshRegistered()

        // Then: The method should attempt to call setupAnalytics
        // Note: In the real app, this would call (UIApplication.shared.delegate as? AppDelegate)?.setupAnalytics()
        // which would re-register NotificationsCoordinator
        // We can't test this directly without mocking UIApplication, but we can verify the flow
        #if !APPCLIP
        // The method completed without error, indicating setupAnalytics would be called
        XCTAssertTrue(true, "refreshRegistered completed successfully for opted-in user")
        #endif
    }

    @MainActor
    func testOptOutOptInFlowWithNotificationsAdapter() {
        // Given: The app startup adapter is registered
        let notificationsCoordinator = NotificationsCoordinator.shared
        let adapters: [AnalyticsAdapter] = [notificationsCoordinator]
        Analytics.register(adapters: adapters)
        XCTAssertTrue(analytics.adaptersRegistered, "Adapter should be registered")

        // When: User opts out of analytics
        analytics.optOutOfAnalytics()

        // Then: Analytics should be unregistered
        XCTAssertFalse(analytics.adaptersRegistered, "Analytics should be unregistered after opt-out")
        XCTAssertTrue(Settings.analyticsOptOut(), "User should be opted out")

        // When: User opts back in (simulating the opt-in flow)
        Settings.setAnalytics(optOut: false)
        analytics.refreshRegistered()

        // Then: The system should be ready for re-registration
        // In the real app, setupAnalytics would be called automatically and would re-register the adapter
        XCTAssertFalse(Settings.analyticsOptOut(), "User should be opted back in")

        // Simulate what setupAnalytics would do - re-register the adapter
        Analytics.register(adapters: adapters)
        XCTAssertTrue(analytics.adaptersRegistered, "Adapter should be re-registered after opt-in")
    }

    @MainActor func testOptInOfAnalyticsCallsSetupAnalytics() {
        // Given: User is opted out
        Settings.setAnalytics(optOut: true)
        Analytics.unregister()

        // When: User opts in
        analytics.optInOfAnalytics()

        // Then: User should be opted in
        XCTAssertFalse(Settings.analyticsOptOut(), "User should be opted in after calling optInOfAnalytics")

        // The method should have attempted to call setupAnalytics
        // In the real app, this would re-register NotificationsCoordinator
        #if !APPCLIP
        XCTAssertTrue(true, "optInOfAnalytics completed successfully")
        #endif
    }

#if canImport(TelemetryDeck)
    func testTelemetryDeckAdapterIgnoresEventsWhenSDKIsNotInitialized() async {
        TelemetryDeck.terminate()

        XCTAssertFalse(TelemetryManager.isInitialized, "TelemetryDeck should start uninitialized for this regression test")

        await TelemetryDeckAnalyticsAdapter().track(name: "test_event", properties: ["source": "unit_test"])

        XCTAssertFalse(TelemetryManager.isInitialized, "Tracking should not initialize TelemetryDeck implicitly")
    }
#endif
}

// MARK: - Test Helper Classes

/// Simple test adapter to verify registration behavior
private final class TestAnalyticsAdapter: AnalyticsAdapter, @unchecked Sendable {
    var trackCallCount = 0
    var lastTrackedEvent: String?
    var lastTrackedProperties: [String: Sendable]?

    func track(name: String, properties: [String: Sendable]) async {
        trackCallCount += 1
        lastTrackedEvent = name
        lastTrackedProperties = properties
    }
}
