import Foundation
@testable import PocketCastsServer
import XCTest

final class TokenAcquisitionTests: XCTestCase {
    private actor Counter {
        private(set) var value = 0

        func increment() {
            value += 1
        }
    }

    /// N concurrent acquirers must share a single underlying acquisition (C.0-3).
    func testConcurrentAcquiresCollapseIntoOneOperation() async throws {
        let serializer = TokenAcquisitionSerializer()
        let operationRuns = Counter()

        let responses = try await withThrowingTaskGroup(of: AuthenticationResponse?.self) { group in
            for _ in 0 ..< 8 {
                group.addTask {
                    try await serializer.acquire {
                        await operationRuns.increment()
                        // Hold the in-flight window open long enough for every task
                        // in the group to reach the serializer.
                        try await Task.sleep(for: .milliseconds(300))
                        return AuthenticationResponse(token: "shared-token", uuid: nil, email: nil, refreshToken: nil, isNewAccount: nil, expiresIn: nil, tokenType: nil)
                    }
                }
            }

            var collected = [AuthenticationResponse?]()
            for try await response in group {
                collected.append(response)
            }
            return collected
        }

        XCTAssertEqual(responses.count, 8)
        XCTAssertTrue(responses.allSatisfy { $0?.token == "shared-token" }, "Every concurrent caller should receive the shared acquisition result")

        let runs = await operationRuns.value
        XCTAssertEqual(runs, 1, "Only one acquisition should ever be in flight")
    }

    /// A failed acquisition must propagate to all waiters and not poison later acquires.
    func testFailedAcquireAllowsSubsequentAcquire() async throws {
        let serializer = TokenAcquisitionSerializer()

        do {
            _ = try await serializer.acquire { throw APIError.UNKNOWN }
            XCTFail("Acquire should rethrow the operation's error")
        } catch {
            XCTAssertEqual(error as? APIError, APIError.UNKNOWN)
        }

        let response = try await serializer.acquire {
            AuthenticationResponse(token: "second-attempt", uuid: nil, email: nil, refreshToken: nil, isNewAccount: nil, expiresIn: nil, tokenType: nil)
        }
        XCTAssertEqual(response?.token, "second-attempt")
    }

    /// The hand-encoded revoke body must match the protobuf wire format of
    /// `TokenRevokeRequest { string refresh_token = 1; }` until the M1 stubs land.
    func testTokenRevokeRequestBodyEncoding() {
        let body = SyncManager.tokenRevokeRequestBody(refreshToken: "abc")
        XCTAssertEqual(body, Data([0x0A, 0x03] + Array("abc".utf8)))

        // Multi-byte varint length: 200 bytes -> 0xC8 0x01.
        let longToken = String(repeating: "x", count: 200)
        let longBody = SyncManager.tokenRevokeRequestBody(refreshToken: longToken)
        XCTAssertEqual(longBody.prefix(3), Data([0x0A, 0xC8, 0x01]))
        XCTAssertEqual(longBody.count, 3 + 200)
    }

    func testTokenRevokeRequestIsAuthenticatedByRefreshTokenNotBearerToken() {
        let request = SyncManager.tokenRevokeRequest(refreshToken: "refresh-credential")

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/user/token/revoke")
        XCTAssertNil(
            request.value(forHTTPHeaderField: ServerConstants.HttpHeaders.authorization),
            "An expired or invalid access token must not prevent refresh-token revocation"
        )
        XCTAssertEqual(request.httpBody, SyncManager.tokenRevokeRequestBody(refreshToken: "refresh-credential"))
    }
}
