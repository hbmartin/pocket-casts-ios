import Foundation
import XCTest

@testable import PocketCastsServer

final class ApiUserChangeResponseTests: XCTestCase {
    func testMessageIDUsesTheCompatibleCamelCaseJSONName() throws {
        let response = try Api_UserChangeResponse(jsonString: #"{"messageId":"password_updated"}"#)

        XCTAssertEqual(response.messageID, "password_updated")
        let encoded = try XCTUnwrap(try response.jsonString().data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: String])
        XCTAssertEqual(object["messageId"], "password_updated")
        XCTAssertNil(object["message_id"])
    }
}
