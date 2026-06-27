@testable import PocketCastsServer
import XCTest

final class SharingServerHandlerTests: XCTestCase {
    func testLegacySharingServerSignatureMatchesServerContract() {
        XCTAssertEqual(
            SharingServerHandler.legacySharingServerSignature(
                for: "20240601123456",
                credential: "legacy-shared-secret"
            ),
            "d802d44e483484bf621d7e165bc3dc9d5a160415"
        )
    }
}
