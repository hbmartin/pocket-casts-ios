import XCTest

@MainActor
class PocketCastsUITestCase: XCTestCase {
    // nonisolated(unsafe): XCTest calls tearDownWithError through a legacy nonisolated
    // override on the same runner thread; all XCUIApplication operations still execute
    // inside MainActor.assumeIsolated before the reference is used.
    nonisolated(unsafe) private(set) var launchedApp: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override nonisolated func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0, let app = launchedApp {
            let payload = MainActor.assumeIsolated {
                Self.failurePayload(for: app)
            }

            let screenshot = XCTAttachment(
                data: payload.screenshotPNG,
                uniformTypeIdentifier: "public.png"
            )
            screenshot.name = "Failure screenshot"

            let hierarchy = XCTAttachment(string: payload.hierarchy)
            hierarchy.name = "Accessibility hierarchy"

            let scenarioAttachment = XCTAttachment(string: payload.scenario)
            scenarioAttachment.name = "Selected UI test scenario"

            let logAttachment = XCTAttachment(string: payload.logs)
            logAttachment.name = "Pocket Casts app logs"

            let attachments = [screenshot, hierarchy, scenarioAttachment, logAttachment]
            for attachment in attachments {
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }

        try super.tearDownWithError()
    }

    private static func failurePayload(for app: XCUIApplication) -> FailureArtifactPayload {
        let scenario = app.launchEnvironment["UI_TEST_SCENARIO"] ?? "live-staging-or-unseeded"
        let logMarker = app.descendants(matching: .any)["uiTestCapturedLogs"]
        let logs = (logMarker.value as? String) ?? "No app logs were captured"
        return FailureArtifactPayload(
            screenshotPNG: app.screenshot().pngRepresentation,
            hierarchy: app.debugDescription,
            scenario: scenario,
            logs: logs
        )
    }

    private struct FailureArtifactPayload: Sendable {
        let screenshotPNG: Data
        let hierarchy: String
        let scenario: String
        let logs: String
    }

    func launchApp(
        additionalArguments: [String] = [],
        additionalEnvironment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        launchedApp = app
        // A fresh install otherwise opens the onboarding carousel instead of the
        // tab bar. This launch argument lands in UserDefaults' NSArgumentDomain
        // (highest priority): MainTabBarController skips onboarding when
        // shouldShowInitialOnboardingFlow is false AND the key exists
        // (hasSeenInitialOnboardingBefore), both of which "0" satisfies at once.
        app.launchArguments += ["-shouldShowInitialOnboardingFlow", "0"]
        app.launchArguments += additionalArguments
        app.launchEnvironment["POCKET_CASTS_UI_TEST_CAPTURE_LOGS"] = "1"
        app.launchEnvironment.merge(additionalEnvironment) { _, new in new }
        app.launch()
        dismissSystemAlerts(reactivating: app)
        return app
    }

    /// System alerts (permission prompts, URL-open confirmations) present in the
    /// springboard session, deactivate the app behind them, and swallow taps —
    /// queries against the app then time out or hit the alert instead.
    func dismissSystemAlerts(reactivating app: XCUIApplication) {
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

    func waitForTabBar(in app: XCUIApplication) {
        // Generous timeout: the first cold launch on a freshly-booted simulator runs
        // DB schema migration and credential setup and can take 30s+ under CI load.
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 90),
                      "App did not reach the main tab bar after launch")
    }

    @discardableResult
    func waitForScenario(
        _ scenario: String,
        in app: XCUIApplication,
        containing expectedFragments: [String]
    ) -> XCUIElement {
        let ready = app.descendants(matching: .any)["uiTestAppReady"]
        XCTAssertTrue(ready.waitForExistence(timeout: 15), "Scenario did not publish its readiness marker")

        let value = ready.value as? String ?? ""
        XCTAssertTrue(value.contains(scenario), "Unexpected scenario readiness value: \(value)")
        for fragment in expectedFragments {
            XCTAssertTrue(value.contains(fragment), "Readiness value did not contain '\(fragment)': \(value)")
        }
        return ready
    }

    func relaunchPreservingScenario(_ app: XCUIApplication) {
        app.terminate()
        app.launchEnvironment["UI_TEST_SCENARIO_MODE"] = "preserve"
        app.launch()
        dismissSystemAlerts(reactivating: app)
        waitForTabBar(in: app)
    }
}

/// Launch-path smoke tests. Unit tests share one long-lived test-host process,
/// so they never re-exercise cold start, AppDelegate's deferred background
/// launch work, or scene lifecycle transitions — the paths where default
/// MainActor isolation regressions surface as executor-assertion traps.
@MainActor
final class SmokeUITests: PocketCastsUITestCase {
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

    private func openFolderNameStep(in app: XCUIApplication) {
        let createFolder = app.buttons["Create New Folder"]
        XCTAssertTrue(createFolder.waitForExistence(timeout: 15), "Library did not expose Create New Folder")
        createFolder.tap()

        for title in ["Organization Podcast One", "Organization Podcast Two"] {
            let pickerRow = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@ AND label CONTAINS 'Not Selected'", title)
            ).firstMatch
            XCTAssertTrue(pickerRow.waitForExistence(timeout: 15), "Folder picker did not show \(title)")
            pickerRow.tap()
        }

        let addPodcasts = app.buttons["Add 2 Podcasts"]
        XCTAssertTrue(addPodcasts.waitForExistence(timeout: 10), "Folder picker did not accept both podcasts")
        addPodcasts.tap()

        XCTAssertTrue(
            app.textFields["Folder name"].waitForExistence(timeout: 10),
            "Folder name field was not shown"
        )
    }

    private func dismissKeyboardIntroductionIfNeeded(in app: XCUIApplication) {
        let keyboardIntroduction = app.otherElements["UIContinuousPathIntroductionView"]
        if keyboardIntroduction.waitForExistence(timeout: 2) {
            keyboardIntroduction.buttons["Continue"].tap()
        }
    }

    // Cold-launch coverage is provided by every test here: each launches the app
    // and waits for the tab bar before exercising its path. Post-launch-settle
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

    func testDeterministicLibraryWithQueueScenario() throws {
        let app = launchApp(additionalEnvironment: [
            "UI_TEST_SCENARIO": "libraryWithQueue"
        ])
        waitForTabBar(in: app)

        waitForScenario(
            "libraryWithQueue",
            in: app,
            containing: ["mode=seed", "podcasts=1", "upNext=2"]
        )

        let seededPodcast = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == 'UI Test Library'")
        ).firstMatch
        XCTAssertTrue(seededPodcast.waitForExistence(timeout: 15), "Seeded podcast was not rendered")
    }

    func testCannedRefreshPreservesSeededEpisodes() throws {
        let app = launchApp(additionalEnvironment: [
            "UI_TEST_SCENARIO": "playbackQueuePersistence",
            "POCKET_CASTS_UI_TEST_EXERCISE_CANNED_REFRESH": "1"
        ])
        waitForTabBar(in: app)
        waitForScenario(
            "playbackQueuePersistence",
            in: app,
            containing: ["mode=seed", "episodes=3", "downloaded=1"]
        )

        let refreshCompleted = app.descendants(matching: .any)["uiTestCannedRefreshCompleted"]
        XCTAssertTrue(refreshCompleted.waitForExistence(timeout: 15), "Canned podcast refresh did not complete")
        let result = refreshCompleted.value as? String ?? ""
        for fragment in ["result=noData", "episodes=3", "archived=0", "downloaded=1"] {
            XCTAssertTrue(result.contains(fragment), "Canned refresh result omitted '\(fragment)': \(result)")
        }

        let podcast = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == 'UI Test Playback Podcast'")
        ).firstMatch
        XCTAssertTrue(podcast.waitForExistence(timeout: 15), "Seeded playback podcast was not rendered")
        podcast.tap()

        XCTAssertTrue(
            app.staticTexts["3 episodes • 0 archived"].waitForExistence(timeout: 15),
            "Canned refresh archived seeded episodes"
        )
    }

    func testPlaybackScenarioUsesLocalDownloadedAudio() throws {
        let app = launchApp(additionalEnvironment: [
            "UI_TEST_SCENARIO": "playbackQueuePersistence"
        ])
        waitForTabBar(in: app)
        waitForScenario(
            "playbackQueuePersistence",
            in: app,
            containing: ["mode=seed", "episodes=3", "downloaded=1"]
        )

        let podcast = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == 'UI Test Playback Podcast'")
        ).firstMatch
        XCTAssertTrue(podcast.waitForExistence(timeout: 15), "Seeded playback podcast was not rendered")
        podcast.tap()

        let downloadedEpisode = app.cells.matching(
            NSPredicate(format: "label CONTAINS 'Playback Episode One' AND label CONTAINS 'Downloaded'")
        ).firstMatch
        XCTAssertTrue(downloadedEpisode.waitForExistence(timeout: 15), "Playback fixture was not downloaded")
        downloadedEpisode.tap()

        let episodePlayButton = app.buttons["Play"].firstMatch
        XCTAssertTrue(episodePlayButton.waitForExistence(timeout: 10), "Episode detail did not expose playback")
        episodePlayButton.tap()

        let playingMiniPlayer = app.buttons.matching(
            NSPredicate(format: "identifier == 'play pause button' AND label == 'Pause'")
        ).firstMatch
        XCTAssertTrue(
            playingMiniPlayer.waitForExistence(timeout: 15),
            "Local downloaded fixture did not enter playing state"
        )
    }

    func testPlaybackAndUpNextPersistAcrossRelaunch() throws {
        let app = launchApp(additionalEnvironment: [
            "UI_TEST_SCENARIO": "playbackQueuePersistence"
        ])
        waitForTabBar(in: app)
        waitForScenario(
            "playbackQueuePersistence",
            in: app,
            containing: ["mode=seed", "podcasts=1", "episodes=3", "upNext=0"]
        )

        let podcast = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == 'UI Test Playback Podcast'")
        ).firstMatch
        XCTAssertTrue(podcast.waitForExistence(timeout: 15), "Seeded playback podcast was not rendered")
        podcast.tap()

        let firstEpisode = app.cells.matching(
            NSPredicate(format: "label CONTAINS 'Playback Episode One'")
        ).firstMatch
        XCTAssertTrue(firstEpisode.waitForExistence(timeout: 15), "First seeded episode was not rendered")
        firstEpisode.tap()

        let episodePlayButton = app.buttons["Play"].firstMatch
        XCTAssertTrue(episodePlayButton.waitForExistence(timeout: 10), "Episode detail did not expose playback")
        episodePlayButton.tap()

        let miniPlayerPlayPauseButton = app.buttons["play pause button"]
        XCTAssertTrue(
            miniPlayerPlayPauseButton.waitForExistence(timeout: 15),
            "Playing an episode did not show the mini-player"
        )

        let secondEpisode = app.cells.matching(
            NSPredicate(format: "label CONTAINS 'Queue Episode Two'")
        ).firstMatch
        XCTAssertTrue(secondEpisode.waitForExistence(timeout: 15), "Second seeded episode was not rendered")
        secondEpisode.swipeRight()

        let playLast = app.buttons["Play Last"]
        XCTAssertTrue(playLast.waitForExistence(timeout: 10), "Episode swipe did not expose Play Last")
        playLast.tap()

        relaunchPreservingScenario(app)
        waitForScenario(
            "playbackQueuePersistence",
            in: app,
            containing: ["mode=preserve", "upNext=2"]
        )

        let restoredMiniPlayer = app.buttons["play pause button"]
        XCTAssertTrue(
            restoredMiniPlayer.waitForExistence(timeout: 15),
            "Relaunch did not restore the mini-player"
        )

        let openPlayerButton = app.buttons["Player"].firstMatch
        XCTAssertTrue(openPlayerButton.waitForExistence(timeout: 10), "Restored mini-player could not be opened")
        openPlayerButton.tap()

        let restoredUpNextButton = app.buttons["Up Next List"]
        XCTAssertTrue(restoredUpNextButton.waitForExistence(timeout: 10), "Full player did not expose Up Next")
        restoredUpNextButton.tap()

        for title in ["Playback Episode One", "Queue Episode Two"] {
            let queuedEpisode = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", title)
            ).firstMatch
            XCTAssertTrue(queuedEpisode.waitForExistence(timeout: 15), "Up Next did not restore \(title)")
        }
    }

    func testFolderOrganizationPersistsAcrossRelaunch() throws {
        let app = launchApp(additionalEnvironment: [
            "UI_TEST_SCENARIO": "folderOrganizationPersistence"
        ])
        waitForTabBar(in: app)
        waitForScenario(
            "folderOrganizationPersistence",
            in: app,
            containing: ["mode=seed", "podcasts=2", "folders=0", "organized=0"]
        )

        openFolderNameStep(in: app)

        let folderName = app.textFields["Folder name"]
        folderName.typeText("UI Journey Folder")
        dismissKeyboardIntroductionIfNeeded(in: app)

        let continueButton = app.buttons["folderNameContinueButton"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10), "Folder name step did not expose Continue")
        continueButton.tap()

        let saveFolder = app.buttons["Save Folder"]
        XCTAssertTrue(saveFolder.waitForExistence(timeout: 10), "Folder color step was not shown")
        saveFolder.tap()

        let folderNavigation = app.navigationBars["UI Journey Folder"]
        XCTAssertTrue(folderNavigation.waitForExistence(timeout: 15), "Created folder did not open")
        for title in ["Organization Podcast One", "Organization Podcast Two"] {
            XCTAssertTrue(
                app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title))
                    .firstMatch.waitForExistence(timeout: 10),
                "Created folder did not contain \(title)"
            )
        }

        relaunchPreservingScenario(app)
        waitForScenario(
            "folderOrganizationPersistence",
            in: app,
            containing: ["mode=preserve", "podcasts=2", "folders=1", "organized=2"]
        )

        let restoredFolder = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'UI Journey Folder'")
        ).firstMatch
        XCTAssertTrue(restoredFolder.waitForExistence(timeout: 15), "Relaunch did not restore the folder")
        restoredFolder.tap()

        for title in ["Organization Podcast One", "Organization Podcast Two"] {
            XCTAssertTrue(
                app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title))
                    .firstMatch.waitForExistence(timeout: 10),
                "Restored folder did not contain \(title)"
            )
        }
    }

    func testFolderNameContinueButtonHasStableIdentifier() throws {
        let app = launchApp(additionalEnvironment: [
            "UI_TEST_SCENARIO": "folderOrganizationPersistence"
        ])
        waitForTabBar(in: app)
        waitForScenario(
            "folderOrganizationPersistence",
            in: app,
            containing: ["mode=seed", "podcasts=2", "folders=0", "organized=0"]
        )
        openFolderNameStep(in: app)

        app.textFields["Folder name"].typeText("Stable Identifier Folder")

        let continueButtons = app.buttons.matching(identifier: "folderNameContinueButton")
        XCTAssertEqual(continueButtons.count, 1, "Folder name step must expose one stable Continue action")
        dismissKeyboardIntroductionIfNeeded(in: app)

        let continueButton = continueButtons.firstMatch
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10), "Stable Continue action disappeared")
        continueButton.tap()

        XCTAssertTrue(
            app.buttons["Save Folder"].waitForExistence(timeout: 10),
            "Stable Continue action did not advance to folder color selection"
        )
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

    /// Calls both NowPlayingHelper artwork request handlers on a detached task.
    /// Without @Sendable, default MainActor isolation traps before the marker appears.
    func testNowPlayingArtworkRequestHandlersRunOffMain() throws {
        let app = launchApp(additionalEnvironment: [
            "POCKET_CASTS_UI_TEST_EXERCISE_ARTWORK_HANDLERS": "1"
        ])
        waitForTabBar(in: app)

        let failed = app.descendants(matching: .any)["mediaConcurrencyArtworkHandlersFailed"]
        let completed = app.descendants(matching: .any)["mediaConcurrencyArtworkHandlersCompleted"]
        XCTAssertTrue(completed.waitForExistence(timeout: 15),
                      failed.exists
                          ? "Artwork handlers ran but returned unexpected images"
                          : "Artwork handlers did not complete off-main")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Posts the three AVAudioSession notifications from a detached task and waits
    /// until the live PlaybackManager has handled every callback on the main actor.
    func testAudioSessionNotificationsPostedOffMainReachPlaybackManager() throws {
        let app = launchApp(additionalEnvironment: [
            "POCKET_CASTS_UI_TEST_EXERCISE_AUDIO_SESSION_NOTIFICATIONS": "1"
        ])
        waitForTabBar(in: app)

        let completed = app.descendants(matching: .any)["mediaConcurrencyAudioSessionNotificationsCompleted"]
        XCTAssertTrue(completed.waitForExistence(timeout: 15),
                      "PlaybackManager did not handle every off-main AVAudioSession notification")
        XCTAssertTrue(app.tabBars.firstMatch.exists,
                      "App lost its main UI while handling audio-session notifications")
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
