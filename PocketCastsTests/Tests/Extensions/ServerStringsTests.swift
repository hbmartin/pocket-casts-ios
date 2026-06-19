import XCTest
@testable import podcasts
import PocketCastsServer

/// Pure-logic tests for Server+Strings.swift: the `APIError.localizedDescription` and
/// `AutoAddLimitReachedAction.description(short:)` mappings. Assertions compare against the same `L10n`
/// values the code returns, so they hold in any locale.
final class ServerStringsTests: XCTestCase {

    func testAPIError_mapsRepresentativeCasesToLocalizedStrings() {
        XCTAssertEqual(APIError.UNKNOWN.localizedDescription, L10n.serverErrorUnknown)
        XCTAssertEqual(APIError.INCORRECT_PASSWORD.localizedDescription, L10n.serverErrorLoginPasswordIncorrect)
        XCTAssertEqual(APIError.EMAIL_TAKEN.localizedDescription, L10n.serverErrorLoginEmailTaken)
        XCTAssertEqual(APIError.NO_CONNECTION.localizedDescription, L10n.playerErrorInternetConnection)
        XCTAssertEqual(APIError.FILES_EXCEEDS_STORAGE.localizedDescription, L10n.serverErrorFilesStorageLimitExceeded)
        XCTAssertEqual(APIError.INVALID_GRANT.localizedDescription, L10n.serverErrorLoginInvalidGrant)
    }

    func testAutoAddLimitReachedAction_stopAdding() {
        XCTAssertEqual(AutoAddLimitReachedAction.stopAdding.description(), L10n.autoAddToUpNextStop)
        XCTAssertEqual(AutoAddLimitReachedAction.stopAdding.description(short: true), L10n.autoAddToUpNextStopShort)
    }

    func testAutoAddLimitReachedAction_addToTopOnly() {
        XCTAssertEqual(AutoAddLimitReachedAction.addToTopOnly.description(), L10n.autoAddToUpNextTopOnly)
        XCTAssertEqual(AutoAddLimitReachedAction.addToTopOnly.description(short: true), L10n.autoAddToUpNextTopOnlyShort)
    }
}
