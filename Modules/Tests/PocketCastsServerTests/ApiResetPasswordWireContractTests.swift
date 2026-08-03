import SwiftProtobuf
import XCTest

@testable import PocketCastsServer

final class ApiResetPasswordWireContractTests: XCTestCase {
    func testEmailUsesEstablishedFieldFour() throws {
        var request = Api_UserResetPasswordRequest()
        request.email = "a"

        // Field 4 with wire type 2 encodes as tag 0x22. A fork-only field such
        // as 1002 would silently decode as unknown on the deployed backend.
        XCTAssertEqual(try request.serializedData(), Data([0x22, 0x01, 0x61]))
    }
}
