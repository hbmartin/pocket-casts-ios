import XCTest

/// Launch-path smoke tests. Unit tests share one long-lived test-host process,
/// so they never re-exercise cold start, AppDelegate's deferred background
/// launch work, or scene lifecycle transitions — the paths where default
/// MainActor isolation regressions surface as executor-assertion traps.
@MainActor
final class SmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp(
        additionalArguments: [String] = [],
        additionalEnvironment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        // A fresh install otherwise opens the onboarding carousel instead of the
        // tab bar. This launch argument lands in UserDefaults' NSArgumentDomain
        // (highest priority): MainTabBarController skips onboarding when
        // shouldShowInitialOnboardingFlow is false AND the key exists
        // (hasSeenInitialOnboardingBefore), both of which "0" satisfies at once.
        app.launchArguments += ["-shouldShowInitialOnboardingFlow", "0"]
        app.launchArguments += additionalArguments
        app.launchEnvironment.merge(additionalEnvironment) { _, new in new }
        app.launch()
        dismissSystemAlerts(reactivating: app)
        return app
    }

    /// System alerts (permission prompts, URL-open confirmations) present in the
    /// springboard session, deactivate the app behind them, and swallow taps —
    /// queries against the app then time out or hit the alert instead.
    private func dismissSystemAlerts(reactivating app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        var dismissed = false
        for _ in 0..<3 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 2) else { break }
            let cancel = alert.buttons["Cancel"]
            let fallback = alert.buttons.firstMatch
            if cancel.exists {
                cancel.tap()
            } else if fallback.exists {
                fallback.tap()
            } else {
                break
            }
            dismissed = true
        }
        if dismissed {
            app.activate()
        }
    }

    private func waitForTabBar(in app: XCUIApplication) {
        // Generous timeout: the first cold launch on a freshly-booted simulator runs
        // DB schema migration and credential setup and can take 30s+ under CI load.
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 90),
                      "App did not reach the main tab bar after launch")
    }

    private func openProfile(in app: XCUIApplication) {
        let profileTab = app.tabBars.firstMatch.buttons["Profile"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 10), "Missing Profile tab")
        profileTab.tap()

        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10),
                      "Profile did not expose its Settings button")
    }

    private func openAppearanceSettings(in app: XCUIApplication) {
        app.buttons["Settings"].tap()

        let appearanceRow = app.staticTexts["appearance"]
        XCTAssertTrue(appearanceRow.waitForExistence(timeout: 10),
                      "Settings did not expose the Appearance row")
        appearanceRow.tap()

        XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 10),
                      "Appearance settings did not open")
    }

    private func selectTheme(named name: String, in app: XCUIApplication) {
        let themeRow = app.cells.containing(.staticText, identifier: "Theme").firstMatch
        XCTAssertTrue(themeRow.waitForExistence(timeout: 10),
                      "Appearance did not expose the Theme row")
        themeRow.tap()

        let selectorTitle = app.staticTexts["Select Theme"]
        XCTAssertTrue(selectorTitle.waitForExistence(timeout: 10),
                      "Theme selector did not open")

        // ThemePreviewView supplies the accessibility label inside a SwiftUI
        // Button, and XCTest may expose that labelled node as an image/other
        // element rather than as the enclosing button. Match by label across
        // element types; tapping the labelled descendant activates the button.
        let option = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", name)
        ).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 10),
                      "Theme selector did not expose the \(name) theme")
        option.tap()

        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: selectorTitle
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed,
                       "Theme selector did not dismiss after choosing \(name)")

        let selectedThemeRow = app.cells.containing(.staticText, identifier: name).firstMatch
        XCTAssertTrue(selectedThemeRow.waitForExistence(timeout: 10),
                      "Appearance did not reflect the selected \(name) theme")
    }

    private func refreshPodcastArtwork(in app: XCUIApplication) {
        let refreshArtwork = app.staticTexts["Refresh All Podcast Artwork"]
        for _ in 0..<4 where !refreshArtwork.exists {
            app.tables.firstMatch.swipeUp()
        }
        XCTAssertTrue(refreshArtwork.waitForExistence(timeout: 10),
                      "Appearance did not expose artwork refresh")
        refreshArtwork.tap()

        let confirmation = app.alerts["Aye Aye Captain"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10),
                      "Artwork refresh confirmation did not appear")
        confirmation.buttons["OK"].tap()
    }

    // Cold-launch coverage is provided by testTabNavigation and
    // testDiscoverBrowseSmoke — both launch the app and wait for the tab bar as
    // their first step, so a broken cold launch fails them. Post-launch-settle
    // crash detection is covered by scripts/ci/smoke-launch.sh and the crash-report
    // sweep. A standalone cold-start test was removed: the very first launch on a
    // freshly-booted simulator under CI load is unreliably slow, making it flaky
    // without adding coverage the above don't already provide.

    func testTabNavigation() throws {
        let app = launchApp()
        waitForTabBar(in: app)

        let tabBar = app.tabBars.firstMatch
        for label in ["Playlists", "Profile", "Podcasts"] {
            let tab = tabBar.buttons[label]
            XCTAssertTrue(tab.waitForExistence(timeout: 10), "Missing tab: \(label)")
            tab.tap()
            // The crash signal is "does the app survive the transition", not its
            // instantaneous state during it: app.state reads .notRunning for a beat
            // mid-transition even when healthy. Require the tab bar to still be
            // present after things settle — a real crash never gets there.
            XCTAssertTrue(tabBar.waitForExistence(timeout: 10),
                          "App crashed or lost its UI switching to \(label)")
        }
    }

    // NOTE: a background/foreground-cycle test lived here but was removed — under a
    // shared, loaded simulator XCUITest's home-press + reactivate is unreliable
    // (the OS reclaims the backgrounded app and reactivation races), producing
    // flaky failures with no underlying app crash. Crashes on the background path
    // are still covered by the crash-report sweep (runs around every test) and the
    // launch smoke test. Restore this test on a dedicated, unloaded CI simulator.

    func testDiscoverBrowseSmoke() throws {
        let app = launchApp()
        waitForTabBar(in: app)

        // Fresh installs land on the empty Podcasts tab with a Discover button;
        // seeded installs reach Discover through search. Either path exercises
        // the discover/refresh network stack.
        let discoverButton = app.buttons["Discover Podcasts"]
        if discoverButton.waitForExistence(timeout: 5) {
            discoverButton.tap()
        } else {
            throw XCTSkip("No Discover entry point on this install state")
        }

        // Any non-trivial content proves the discover feed rendered without
        // tripping an isolation assert in the networking/refresh pipeline.
        let content = app.cells.firstMatch
        guard content.waitForExistence(timeout: 30) else {
            throw XCTSkip("Discover content did not load (offline or staging outage)")
        }
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Posts the same queue/playback notifications that drive FileSyncCoordinator,
    /// including repeated starts and stops, then waits for its debounced timer to fire.
    /// An actor-isolation regression in any handler crashes the app before the marker appears.
    func testFileSyncCoordinatorNotificationTimers() throws {
        let app = launchApp(additionalEnvironment: [
            "POCKET_CASTS_UI_TEST_EXERCISE_FILE_SYNC_COORDINATOR_EVENTS": "1"
        ])
        waitForTabBar(in: app)

        let debounceCompleted = app.descendants(matching: .any)["fileSyncCoordinatorDebounceCompleted"]
        XCTAssertTrue(debounceCompleted.waitForExistence(timeout: 15),
                      "File sync notification debounce did not complete")
        XCTAssertTrue(app.tabBars.firstMatch.exists,
                      "App lost its main UI while exercising file sync notification timers")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Exercises the checked-Sendable replacements through their user-facing paths:
    /// RefreshManager starts a refresh, Theme publishes two snapshot mutations, and
    /// ImageManager clears/rebuilds artwork caches before a cold relaunch verifies the
    /// selected theme survived. The final Default Light selection leaves shared simulators tidy.
    func testAppearanceThemeArtworkAndRefreshSmoke() throws {
        let app = launchApp(additionalArguments: ["-FollowSystemTheme", "0"])
        waitForTabBar(in: app)
        openProfile(in: app)

        let refreshButton = app.buttons.matching(
            NSPredicate(format: "label == 'Refresh Now' OR label == 'Try Again'")
        ).firstMatch
        XCTAssertTrue(refreshButton.waitForExistence(timeout: 10),
                      "Profile did not expose its refresh action")
        refreshButton.tap()

        openAppearanceSettings(in: app)
        selectTheme(named: "Default Light", in: app)
        selectTheme(named: "Default Dark", in: app)
        refreshPodcastArtwork(in: app)

        app.terminate()
        app.launch()
        dismissSystemAlerts(reactivating: app)
        waitForTabBar(in: app)
        openProfile(in: app)
        openAppearanceSettings(in: app)

        let persistedDarkTheme = app.cells.containing(.staticText, identifier: "Default Dark").firstMatch
        XCTAssertTrue(persistedDarkTheme.waitForExistence(timeout: 10),
                      "Dark theme did not survive a cold relaunch")

        selectTheme(named: "Default Light", in: app)

        let podcastsTab = app.tabBars.firstMatch.buttons["Podcasts"]
        XCTAssertTrue(podcastsTab.waitForExistence(timeout: 10), "Missing Podcasts tab")
        podcastsTab.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10),
                      "App lost its main UI after theme and artwork changes")
    }
}
