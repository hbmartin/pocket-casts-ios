import XCTest

/// Real-service canaries live in their own test plan so staging availability
/// never weakens the deterministic UI signal.
@MainActor
final class LiveStagingUITests: PocketCastsUITestCase {
    func testDiscoverBrowseAgainstStaging() throws {
        let app = launchApp()
        waitForTabBar(in: app)

        let discoverButton = app.buttons["Discover Podcasts"]
        guard discoverButton.waitForExistence(timeout: 5) else {
            XCTFail("Fresh staging install did not expose Discover Podcasts")
            return
        }
        discoverButton.tap()

        XCTAssertTrue(
            app.cells.firstMatch.waitForExistence(timeout: 30),
            "Staging Discover content did not load"
        )
        XCTAssertEqual(app.state, .runningForeground)
    }
}
