import XCTest

@testable import podcasts

final class StringCredentialsTests: XCTestCase {

    func testEmptyValueIsTreatedAsMissing() {
        XCTAssertTrue("".isMissingOrPlaceholderCredential)
    }

    func testUnsubstitutedPlaceholderIsDetected() {
        XCTAssertTrue("%{telemetry_deck_app_id}".isMissingOrPlaceholderCredential)
        XCTAssertTrue("%{bitdrift_sdk_key}".isMissingOrPlaceholderCredential)
        XCTAssertTrue("%{}".isMissingOrPlaceholderCredential)
    }

    func testRealCredentialIsConfigured() {
        XCTAssertFalse("ABC123-real-app-id".isMissingOrPlaceholderCredential)
        XCTAssertFalse("https://example.com".isMissingOrPlaceholderCredential)
    }

    func testValueNotBoundedByPlaceholderDelimitersIsConfigured() {
        XCTAssertFalse("prefix-%{token}-suffix".isMissingOrPlaceholderCredential)
        XCTAssertFalse("%{unterminated".isMissingOrPlaceholderCredential)
        XCTAssertFalse("unstarted}".isMissingOrPlaceholderCredential)
    }
}
