import XCTest

private extension Config {
    static let step_02_podcastName = "Serial"
    static let step_03_podcastName = "Connected"
    static let step_03_episodeKey = "377"
    static let step_05_podcastName = "All In The Mind"
    static let step_06_podcastName = "Distributed, with Matt Mullenweg"
    static let step_06_episodeKey = "Distributed by Default"
}

class iPhone_GenerateScreenshots: GenerateScreenshots {
    func test_generateScreenshots() throws {
        // 01 - Podcast List (Default Light Theme)
        selectTab(.podcasts)
        snapshot("01_Podcast_List")

        // 02 - Podcast Page (Default Light Theme)
        scrollToAndTap(app.buttons[Config.step_02_podcastName])
        snapshot("02_Podcast_Page_Default_Light_Theme")

        // 02 Teardown
        app.buttons["Close"].waitForThenTap()

        // 03 - Player With Chapters
        scrollToAndTap(app.buttons[Config.step_03_podcastName])
        openEpisode(Config.step_03_episodeKey)

        hittablePlayButton.waitForThenTap()

        if !app.buttons["Close player"].exists {
            app.buttons["Player"].waitForThenTap()
        }

        snapshot("03_Player_With_Chapters")

        // 03 Teardown
        hittablePlayButton.waitForThenTap()
        app.buttons["Close player"].waitForThenTap()
        app.buttons["Close"].waitForThenTap()

        // 04 - Theme Selection
        navigateToApperance()
        enableSystemThemeMatching()
        snapshot("04_Theme_Options")

        // 04 Teardown
        backButton.waitForThenTap()
        backButton.waitForThenTap()
        selectTab(.podcasts)

        // 06 - Episode Details (Default Light Theme)
        scrollToAndTap(app.buttons[Config.step_06_podcastName])
        openEpisode(Config.step_06_episodeKey)
        snapshot("06_Episode_Details")

        // 06 Teardown
        app.buttons["Close"].firstMatch.waitForThenTap()
        app.buttons["Close"].firstMatch.waitForThenTap()

        // 07 - Filters (Default Light Theme)
        selectTab(.filters)
        app.cells.firstMatch.waitForThenTap()

        app.buttons["expandFilter"].waitForThenTap()
        snapshot("07_Filters")

        // 07 Teardown
        backButton.waitForThenTap()
        selectTab(.podcasts)
    }

    func test_generateScreenshots_darkMode() throws {
        // 05 - Podcast Page (Default Dark Theme)
        navigateToApperance()
        enableSystemThemeMatching()
        backButton.waitForThenTap()
        backButton.waitForThenTap()
        selectTab(.podcasts)

        scrollToAndTap(app.buttons[Config.step_05_podcastName])
        snapshot("05_Podcast_Page_Default_Dark_Theme")

        // 05 Teardown
        app.buttons["Close"].waitForThenTap()
    }
}
