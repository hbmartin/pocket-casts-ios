import XCTest
@testable import PocketCastsServer

final class ServerConverterTests: XCTestCase {

    // client raw values: dateAdded=1, titleAtoZ=2, episodeDate=5, custom=6, recentlyPlayed=7
    // server raw values: dateAdded=0, titleAtoZ=1, episodeDate=2, custom=3, recentlyPlayed=4
    private let pairs: [(client: Int, server: Int32)] = [
        (1, 0), (2, 1), (5, 2), (6, 3), (7, 4)
    ]

    func testConvertToServerSortType() {
        for pair in pairs {
            XCTAssertEqual(ServerConverter.convertToServerSortType(clientType: pair.client), pair.server)
        }
    }

    func testConvertToClientSortType() {
        for pair in pairs {
            XCTAssertEqual(ServerConverter.convertToClientSortType(serverType: pair.server), pair.client)
        }
    }

    func testRoundTripIsStable() {
        for pair in pairs {
            let server = ServerConverter.convertToServerSortType(clientType: pair.client)
            XCTAssertEqual(ServerConverter.convertToClientSortType(serverType: server), pair.client)
        }
    }

    func testUnknownValuesFallBackToDateAdded() {
        XCTAssertEqual(ServerConverter.convertToServerSortType(clientType: 999), 0, "unknown client -> dateAdded server")
        XCTAssertEqual(ServerConverter.convertToClientSortType(serverType: 99), 1, "unknown server -> dateAdded client")
    }
}
