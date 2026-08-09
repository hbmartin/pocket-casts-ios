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

    private func openBackupRestoreSettings(in app: XCUIApplication) {
        openProfile(in: app)
        app.buttons["Settings"].tap()

        let backupRestoreRow = app.staticTexts["backupRestore"]
        for _ in 0..<5 where !backupRestoreRow.exists {
            app.tables.firstMatch.swipeUp()
        }
        XCTAssertTrue(backupRestoreRow.waitForExistence(timeout: 10),
                      "Settings did not expose Backup & Restore")
        backupRestoreRow.tap()

        XCTAssertTrue(app.navigationBars["Backup & Restore"].waitForExistence(timeout: 10),
                      "Backup & Restore settings did not open")
    }

    private func assertPR264Harness(
        scenario: String,
        expectedFragments: [String]
    ) {
        let app = launchApp(additionalEnvironment: [
            "POCKET_CASTS_UI_TEST_EXERCISE_PR264_FIX": scenario
        ])
        waitForTabBar(in: app)

        let failed = app.descendants(matching: .any)["pr264FixFailed"]
        let completed = app.descendants(matching: .any)["pr264FixCompleted"]
        guard completed.waitForExistence(timeout: 20) else {
            XCTFail(
                failed.exists
                    ? "PR #264 \(scenario) harness failed: \(failed.value as? String ?? "unknown error")"
                    : "PR #264 \(scenario) harness did not complete"
            )
            return
        }

        let value = completed.value as? String ?? ""
        for fragment in expectedFragments {
            XCTAssertTrue(value.contains(fragment),
                          "PR #264 \(scenario) result omitted '\(fragment)': \(value)")
        }
        XCTAssertEqual(app.state, .runningForeground)
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

    func testBackupRestoreScreenPresentsDestructiveRestoreConfirmation() throws {
        let app = launchApp()
        waitForTabBar(in: app)
        openBackupRestoreSettings(in: app)

        XCTAssertTrue(app.buttons["backupRestoreBackupNow"].exists,
                      "Backup action did not expose its stable identifier")
        let restore = app.buttons["backupRestoreRestore"]
        XCTAssertTrue(restore.exists, "Restore action did not expose its stable identifier")
        restore.tap()

        let confirmation = app.alerts["Restore From Backup?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10),
                      "Restore did not require destructive confirmation")
        XCTAssertTrue(confirmation.buttons["Restore From Backup"].exists,
                      "Restore confirmation did not expose its destructive action")
        confirmation.buttons["Cancel"].tap()
        XCTAssertFalse(confirmation.exists, "Restore confirmation did not dismiss")
    }

    func testPR263BackupRestoreAndSecurityFixes() throws {
        let app = launchApp(additionalEnvironment: [
            "UI_TEST_SCENARIO": "libraryWithQueue",
            "POCKET_CASTS_UI_TEST_EXERCISE_PR263_FIXES": "1"
        ])
        waitForTabBar(in: app)
        waitForScenario("libraryWithQueue", in: app, containing: ["mode=seed"])

        let failed = app.descendants(matching: .any)["pr263FixesFailed"]
        let completed = app.descendants(matching: .any)["pr263FixesCompleted"]
        XCTAssertTrue(completed.waitForExistence(timeout: 20),
                      failed.exists
                          ? "PR #263 harness failed: \(failed.value as? String ?? "unknown error")"
                          : "PR #263 harness did not complete")

        let value = completed.value as? String ?? ""
        for fragment in [
            "restore=atomic",
            "folderCache=refreshed",
            "backupFolder=stable"
        ] {
            XCTAssertTrue(value.contains(fragment),
                          "PR #263 result omitted '\(fragment)': \(value)")
        }
    }

    func testPR264OpmlImportStateRemainsAtomicAcrossConcurrentCallbacks() throws {
        assertPR264Harness(
            scenario: "opmlImportState",
            expectedFragments: ["opmlState=atomic", "responses=200", "failures=400"]
        )
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

/// Read Aloud's end-to-end path, which unit tests structurally cannot reach.
///
/// Everything between "commit the document" and "there is an episode" runs
/// across a queue, a synthesizer callback, an AVMutableComposition and a
/// materializer — and until this existed the only thing that had ever run all
/// of it together was one manual pass. The system document picker is
/// out-of-process and undrivable, which is exactly why the compose screen
/// exists: it puts text into the same pipeline through UI we own.
///
/// Uses the built-in Apple voices deliberately — free, offline, and no API key,
/// so this is safe to run anywhere. The provider path is verified in
/// PocketCastsReadAloudTests against a stubbed transport.
@MainActor
final class ReadAloudUITests: PocketCastsUITestCase {
    /// A fresh title per run: even with a reset library, a failed run can leave
    /// a document behind, and a fixed title would then match the wrong one.
    private lazy var documentTitle = "Narration \(UUID().uuidString.prefix(8))"

    /// Launches through a seeded scenario, which resets the database — including
    /// the Read Aloud tables. Without it the library accumulates documents
    /// across runs and "the delete button" stops being a single element.
    private func launchWithCleanLibrary() -> XCUIApplication {
        let app = launchApp(additionalEnvironment: ["UI_TEST_SCENARIO": "libraryWithQueue"])
        waitForTabBar(in: app)
        waitForScenario("libraryWithQueue", in: app, containing: ["mode=seed"])
        return app
    }

    private func openReadAloudLibrary(in app: XCUIApplication) {
        let profileTab = app.tabBars.firstMatch.buttons["Profile"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 10), "Missing Profile tab")
        profileTab.tap()

        let filesRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == 'Files'")
        ).firstMatch
        XCTAssertTrue(filesRow.waitForExistence(timeout: 10), "Profile did not expose the Files row")
        filesRow.tap()

        let optionsButton = app.buttons["Sort and Options"]
        XCTAssertTrue(optionsButton.waitForExistence(timeout: 10), "Files did not expose its options menu")
        optionsButton.tap()

        let readAloudAction = app.buttons["Read Aloud"]
        XCTAssertTrue(readAloudAction.waitForExistence(timeout: 10),
                      "Files options did not offer Read Aloud — is the feature flag off?")
        readAloudAction.tap()

        XCTAssertTrue(app.buttons["readAloudComposeButton"].waitForExistence(timeout: 10),
                      "Read Aloud library did not open")
    }

    private func composeDocument(text: String, in app: XCUIApplication) {
        app.buttons["readAloudComposeButton"].tap()

        let titleField = app.textFields["readAloudComposeTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), "Compose screen did not expose its title field")

        let editor = app.textViews["readAloudComposeTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "Compose screen did not expose its text editor")
        // The editor takes focus on appear, so the keyboard introduction (if the
        // simulator is showing it) lands here rather than on the first tap.
        dismissKeyboardIntroductionIfNeeded(in: app)
        editor.tap()
        editor.typeText(text)

        titleField.tap()
        titleField.typeText(documentTitle)

        let next = app.buttons["readAloudComposeNextButton"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "Compose screen did not expose Next")
        XCTAssertTrue(next.isEnabled, "Next stayed disabled with text entered")
        next.tap()
    }

    private func dismissKeyboardIntroductionIfNeeded(in app: XCUIApplication) {
        let keyboardIntroduction = app.otherElements["UIContinuousPathIntroductionView"]
        if keyboardIntroduction.waitForExistence(timeout: 2) {
            keyboardIntroduction.buttons["Continue"].tap()
        }
    }

    /// Types text, narrates it, and requires a real episode at the end.
    ///
    /// The final assertion is deliberately the episode in Files rather than the
    /// library's own status row: a narration can reach `completed` with the
    /// UserEpisode never materialized, and that failure would be invisible from
    /// the screen that just rendered it.
    func testComposedTextBecomesAPlayableEpisode() throws {
        let app = launchWithCleanLibrary()
        openReadAloudLibrary(in: app)

        composeDocument(
            text: "The kettle had boiled twice before anyone noticed. "
                + "Outside, the street was doing its usual impression of being asleep.",
            in: app
        )

        let narrateButton = app.buttons["readAloudNarrateButton"]
        XCTAssertTrue(narrateButton.waitForExistence(timeout: 10), "Review sheet did not open")
        XCTAssertTrue(narrateButton.isEnabled,
                      "Narrate was disabled — the built-in engine needs no confirmation and no key")
        narrateButton.tap()

        // Generous: synthesis, the AVMutableComposition assembly and the AAC
        // re-encode all happen here, on a simulator that may be under load.
        let completed = app.descendants(matching: .any)["readAloudNarration.completed"]
        let failed = app.descendants(matching: .any)["readAloudNarration.failed"]
        XCTAssertTrue(completed.waitForExistence(timeout: 240),
                      failed.exists
                          ? "The narration failed to render"
                          : "The narration never reached completed")

        app.navigationBars.buttons.firstMatch.tap()

        let episode = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", documentTitle)
        ).firstMatch
        XCTAssertTrue(episode.waitForExistence(timeout: 30),
                      "The narration completed but no episode appeared in Files")
    }

    /// The one Read Aloud path that can spend money unattended.
    ///
    /// `CreateNarrationIntent` is invoked by the Shortcuts app, out of process,
    /// so no UI test can drive it and no unit test can start it — it runs here
    /// through an in-app harness instead. All three runs use the same text and
    /// the same stored key; only the engine and the consent flag differ.
    func testTheIntentRefusesToSpendQuotaWithoutConsent() throws {
        let app = launchApp(additionalEnvironment: [
            "UI_TEST_SCENARIO": "libraryWithQueue",
            "POCKET_CASTS_UI_TEST_EXERCISE_READ_ALOUD_INTENT": "1"
        ])
        waitForTabBar(in: app)

        let failed = app.descendants(matching: .any)["readAloudIntentFailed"]
        let completed = app.descendants(matching: .any)["readAloudIntentCompleted"]
        XCTAssertTrue(completed.waitForExistence(timeout: 60),
                      failed.exists
                          ? "Intent harness failed: \(failed.value as? String ?? "unknown")"
                          : "Intent harness did not complete")

        let result = completed.value as? String ?? ""

        XCTAssertTrue(result.contains("paidUnconfirmed=paidNarrationNotConfirmed"),
                      "A paid narration ran without consent: \(result)")
        // Getting as far as the voice list proves consent was the only thing
        // stopping the run above — not a missing key or a disabled feature.
        XCTAssertTrue(result.contains("paidConfirmed=noVoiceAvailable"),
                      "With consent the intent should have passed the gate: \(result)")
        XCTAssertTrue(result.contains("free=enqueued"),
                      "The free engine must ignore the consent flag: \(result)")
    }

    /// The document outlives its narration — the whole reason the two are
    /// separate records (ADR-0020). Deleting the episode must leave the text
    /// behind, ready to narrate again.
    func testDeletingANarrationLeavesTheDocument() throws {
        let app = launchWithCleanLibrary()
        openReadAloudLibrary(in: app)
        composeDocument(text: "A short paragraph is enough to render.", in: app)

        app.buttons["readAloudNarrateButton"].tap()
        let completed = app.descendants(matching: .any)["readAloudNarration.completed"]
        XCTAssertTrue(completed.waitForExistence(timeout: 240), "The narration never reached completed")

        let deleteNarration = app.buttons["Delete Recording"]
        XCTAssertTrue(deleteNarration.waitForExistence(timeout: 10),
                      "A completed narration did not offer to be deleted")
        deleteNarration.tap()

        XCTAssertTrue(completed.waitForNonExistence(timeout: 15), "The narration row did not go away")

        let document = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", documentTitle)
        ).firstMatch
        XCTAssertTrue(document.waitForExistence(timeout: 10),
                      "Deleting the narration took the document with it")
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Narrate Again'")).firstMatch.exists,
            "The surviving document could not be narrated again"
        )
    }
}

/// Reporting-only performance baselines (Deferred Item 39): cold launch, podcast
/// page entry and episode card entry over the deterministic seeded library — no
/// scrolling (simulator scroll timings are too noisy to baseline). Runs in its
/// own PerformanceUITests plan; `scripts/ci/perf-report.rb` turns the measured
/// output into a delta table against `scripts/ci/perf-baselines.json`. Nothing
/// here gates CI until variance is characterized.
///
/// Lives in this file rather than its own because PocketCastsUITests is not a
/// file-system-synchronized folder — new files need project surgery, new types
/// don't.
@MainActor
final class PerformanceUITests: PocketCastsUITestCase {
    private static let scenarioEnvironment = ["UI_TEST_SCENARIO": "libraryWithQueue"]

    func testColdLaunchPerformance() {
        // First launch seeds the scenario; measured relaunches preserve it so the
        // timing covers launch work, not the destructive DB wipe + reseed.
        let app = launchApp(additionalEnvironment: Self.scenarioEnvironment)
        waitForTabBar(in: app)
        app.terminate()

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            let measured = XCUIApplication()
            measured.launchArguments += ["-shouldShowInitialOnboardingFlow", "0"]
            measured.launchEnvironment["UI_TEST_SCENARIO"] = "libraryWithQueue"
            measured.launchEnvironment["UI_TEST_SCENARIO_MODE"] = "preserve"
            measured.launch()
        }
    }

    func testPodcastPageEntryPerformance() {
        let app = launchApp(additionalEnvironment: Self.scenarioEnvironment)
        waitForTabBar(in: app)
        waitForScenario("libraryWithQueue", in: app, containing: [])

        let podcastCell = app.staticTexts["UI Test Library"].firstMatch
        XCTAssertTrue(podcastCell.waitForExistence(timeout: 30), "Seeded podcast not visible in the grid")

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric()], options: options) {
            podcastCell.tap()
            let episodeRow = app.staticTexts["Queued Episode One"].firstMatch
            XCTAssertTrue(episodeRow.waitForExistence(timeout: 30), "Podcast page did not show its episodes")
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(podcastCell.waitForExistence(timeout: 30), "Did not return to the podcast grid")
        }
    }

    func testEpisodeCardEntryPerformance() {
        let app = launchApp(additionalEnvironment: Self.scenarioEnvironment)
        waitForTabBar(in: app)
        waitForScenario("libraryWithQueue", in: app, containing: [])

        let podcastCell = app.staticTexts["UI Test Library"].firstMatch
        XCTAssertTrue(podcastCell.waitForExistence(timeout: 30))
        podcastCell.tap()
        let episodeRow = app.staticTexts["Queued Episode One"].firstMatch
        XCTAssertTrue(episodeRow.waitForExistence(timeout: 30))

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric()], options: options) {
            episodeRow.tap()
            // The episode card is a sheet; its action strip is the readiness signal.
            // Exclude the mini-player's play/pause button (identifier "play pause
            // button"), which also carries the "Play" label when paused.
            let card = app.buttons.matching(
                NSPredicate(format: "label == 'Play' AND identifier != 'play pause button'")
            ).firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 30), "Episode card did not show its action strip")
            let closeButton = app.buttons["Close"]
            XCTAssertTrue(closeButton.waitForExistence(timeout: 30), "Episode card did not show its Close control")
            closeButton.tap()
            XCTAssertTrue(card.waitForNonExistence(timeout: 30), "Episode card did not dismiss")
            XCTAssertTrue(episodeRow.waitForExistence(timeout: 30), "Episode card did not dismiss")
        }
    }
}
