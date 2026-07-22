import XCTest

@testable import PocketCastsServer

final class SocialProfileConfigurationTests: XCTestCase {
    func testConfigurationMapsCustomizedProfileFields() {
        var configuration = SocialProfile.Configuration(
            userId: "user-id",
            handle: "listener",
            displayName: "Listener"
        )
        configuration.bio = "Podcasts and long walks"
        configuration.avatarURL = "https://example.com/avatar.png"
        configuration.termsVersion = 3
        configuration.bioVisibility = .public
        configuration.statsVisibility = .followersOnly
        configuration.requireFollowApproval = true
        configuration.socialPushDisabled = 4
        configuration.hideFromDiscovery = true
        configuration.curator = true

        let profile = SocialProfile(configuration: configuration)

        XCTAssertEqual(profile.userId, "user-id")
        XCTAssertEqual(profile.bio, "Podcasts and long walks")
        XCTAssertEqual(profile.avatarURL, "https://example.com/avatar.png")
        XCTAssertEqual(profile.termsVersion, 3)
        XCTAssertEqual(profile.bioVisibility, .public)
        XCTAssertEqual(profile.statsVisibility, .followersOnly)
        XCTAssertTrue(profile.requireFollowApproval)
        XCTAssertEqual(profile.socialPushDisabled, 4)
        XCTAssertTrue(profile.hideFromDiscovery)
        XCTAssertTrue(profile.curator)
    }

    func testIdentityInitializerRetainsPrivacySafeDefaults() {
        let profile = SocialProfile(userId: "user-id", handle: "listener", displayName: "Listener")

        XCTAssertEqual(profile.avatarVisibility, .private)
        XCTAssertEqual(profile.bioVisibility, .private)
        XCTAssertEqual(profile.socialPushDisabled, 0)
        XCTAssertFalse(profile.hideFromDiscovery)
        XCTAssertFalse(profile.curator)
    }
}
