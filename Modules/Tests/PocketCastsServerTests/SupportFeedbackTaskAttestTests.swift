import CryptoKit
import Foundation
import XCTest
@testable import PocketCastsServer
import PocketCastsUtils

/// Verifies the feedback retrofit onto the App Attest contract
/// (docs/AppAttest.md): the POST carries assertion headers computed over the
/// exact body bytes when attestation is available, and still goes out
/// unattested (never failing the send) when it is not.
final class SupportFeedbackTaskAttestTests: XCTestCase {

    private func sendFeedback(backend: AppAttestBackendMock, attester: AppAttestKeyServiceMock) -> Bool {
        // Central-lane wiring: the connection's origin policy matches the host the
        // task posts to, so URLConnection itself routes the POST through the
        // injected AppAttestService — the same path production requests take.
        let service = AppAttestService(attester: attester, urlConnection: backend.connection, keychain: InMemoryKeychainStore())
        let policy = ServerOriginPolicy(
            buildOrigin: ServerConstants.Urls.api(),
            defaults: UserDefaults(suiteName: "SupportFeedbackTaskAttestTests.ephemeral") ?? .standard,
            // The unit-test plan resolves api() to a loopback HTTP origin.
            allowInsecureLoopback: true,
            pinsOrigin: false
        )
        let connection = URLConnection(
            handler: MockRequestHandler(handler: backend.handle),
            originPolicy: policy,
            appAttestService: service
        )

        let sent = expectation(description: "feedback completion called")
        let result = UncheckedSendableBox(false)
        let task = SupportFeedbackTask(report: FeedbackReport(message: "It broke", subject: "Bug"),
                                       urlConnection: connection) { success in
            result.value = success
            sent.fulfill()
        }
        // Drive the request directly (anonymous → no token machinery involved).
        task.startRequest(feedbackType: .anonymous)
        wait(for: [sent], timeout: 15)
        return result.value
    }

    func testFeedbackPostCarriesAssertionHeadersOverExactBody() throws {
        let backend = AppAttestBackendMock()
        let attester = AppAttestKeyServiceMock()

        XCTAssertTrue(sendFeedback(backend: backend, attester: attester), "Feedback send should succeed")

        // Enrollment ran lazily, then the feedback POST carried the headers.
        XCTAssertEqual(backend.state.withLock { $0.enrollBodies.count }, 1)
        let feedbackRequest = try XCTUnwrap(backend.state.withLock { $0.otherRequests.first })
        XCTAssertEqual(feedbackRequest.url?.path.hasSuffix("anonymous/feedback"), true)
        XCTAssertEqual(feedbackRequest.value(forHTTPHeaderField: AppAttestService.HeaderNames.keyId), "key-1")
        XCTAssertEqual(feedbackRequest.value(forHTTPHeaderField: AppAttestService.HeaderNames.assertion),
                       Data("assertion-key-1".utf8).base64EncodedString())

        // The assertion signed SHA256 of the canonical request derived from the
        // exact method, path, query and body bytes that were POSTed.
        let canonical = try AppAttestCanonicalRequest.data(for: feedbackRequest)
        let assertionCall = try XCTUnwrap(attester.state.withLock { $0.assertionCalls.first })
        XCTAssertEqual(assertionCall.clientDataHash, Data(SHA256.hash(data: canonical)))
    }

    func testFeedbackStillSendsUnattestedWhenAttestationUnsupported() throws {
        let backend = AppAttestBackendMock()
        let attester = AppAttestKeyServiceMock(supported: false)

        XCTAssertTrue(sendFeedback(backend: backend, attester: attester), "Unattested feedback send must still succeed")

        XCTAssertEqual(backend.state.withLock { $0.challengeCount }, 0)
        let feedbackRequest = try XCTUnwrap(backend.state.withLock { $0.otherRequests.first })
        XCTAssertNil(feedbackRequest.value(forHTTPHeaderField: AppAttestService.HeaderNames.keyId))
        XCTAssertNil(feedbackRequest.value(forHTTPHeaderField: AppAttestService.HeaderNames.assertion))
    }
}
