import XCTest
import SwiftProtobuf
@testable import PocketCastsServer

/// End-to-end proof of the Swift↔Go social wire contract against the REAL
/// local backend (docs/Social.md "backend live before ship"). Runs only when
/// `POCKET_CASTS_SERVER_BASE_URL` is set (the "Pocket Casts Local" scheme
/// points it at the Docker backend on 127.0.0.1:8000) — skipped everywhere
/// else. When the env var IS set, an unreachable backend is a failure: this
/// suite exists to catch contract drift, not to be skipped past.
///
/// Uses URLSession + the generated `Api_*` messages directly (no app global
/// state), registering throwaway accounts per run. Mirrors the backend's
/// `TestSocialIdentityLoop` e2e test.
final class SocialLocalBackendE2ETests: XCTestCase {
    private var baseURL: URL!

    override func setUpWithError() throws {
        guard let raw = ProcessInfo.processInfo.environment["POCKET_CASTS_SERVER_BASE_URL"],
              let url = URL(string: raw) else {
            throw XCTSkip("POCKET_CASTS_SERVER_BASE_URL not set — run under the 'Pocket Casts Local' scheme with the Docker backend up")
        }
        baseURL = url
    }

    func testSocialFoundationLoop() async throws {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let handle = "ios_e2e_\(suffix)"

        // Register two throwaway accounts.
        let (tokenA, _) = try await register(email: "ios-social-a-\(suffix)@e2e.test")
        let (tokenB, uuidB) = try await register(email: "ios-social-b-\(suffix)@e2e.test")

        // Availability: fresh handle claimable, normalization applied, reserved word refused.
        var availability = Api_HandleAvailabilityRequest()
        availability.handle = "  @\(handle.uppercased()) "
        var (status, body) = try await post("social/handle/availability", token: tokenA, message: availability)
        XCTAssertEqual(status, 200)
        var availResponse = try Api_HandleAvailabilityResponse(serializedBytes: body)
        XCTAssertEqual(availResponse.status, .available)
        XCTAssertEqual(availResponse.normalizedHandle, handle)

        availability.handle = "admin"
        (status, body) = try await post("social/handle/availability", token: tokenA, message: availability)
        XCTAssertEqual(status, 200)
        availResponse = try Api_HandleAvailabilityResponse(serializedBytes: body)
        XCTAssertEqual(availResponse.status, .reserved)

        // Join as A: profile created, all visibility private by default (ADR-0006).
        var join = Api_JoinRequest()
        join.handle = handle
        join.acceptedTermsVersion = 1
        join.displayName = "iOS E2E Person"
        (status, body) = try await post("social/join", token: tokenA, message: join)
        XCTAssertEqual(status, 200)
        let joined = try Api_JoinResponse(serializedBytes: body)
        XCTAssertEqual(joined.profile.handle, handle)
        XCTAssertEqual(joined.profile.bioVisibility, .private)
        XCTAssertEqual(joined.profile.statsVisibility, .private)
        XCTAssertTrue(joined.profile.avatarURL.isEmpty, "avatars are deferred from this slice")

        // Same handle is now taken; B's claim loses with 409.
        availability.handle = handle
        (status, body) = try await post("social/handle/availability", token: tokenB, message: availability)
        XCTAssertEqual(status, 200)
        availResponse = try Api_HandleAvailabilityResponse(serializedBytes: body)
        XCTAssertEqual(availResponse.status, .taken)

        (status, _) = try await post("social/join", token: tokenB, message: join)
        XCTAssertEqual(status, 409)

        // Own-profile get, then update making the bio public.
        (status, body) = try await post("social/profile/get", token: tokenA, message: Api_ProfileGetRequest())
        XCTAssertEqual(status, 200)
        let fetched = try Api_ProfileResponse(serializedBytes: body)
        XCTAssertEqual(fetched.profile.displayName, "iOS E2E Person")

        var update = Api_ProfileUpdateRequest()
        update.displayName = "iOS E2E Person"
        update.bio = "hello from the iOS e2e suite"
        update.bioVisibility = .public
        (status, body) = try await post("social/profile/update", token: tokenA, message: update)
        XCTAssertEqual(status, 200)
        let updated = try Api_ProfileResponse(serializedBytes: body)
        XCTAssertEqual(updated.profile.bioVisibility, .public)
        XCTAssertEqual(updated.profile.statsVisibility, .private, "unspecified folds to private")
        XCTAssertEqual(updated.profile.handle, handle, "handle is immutable")

        // Public read as B: public bio visible, private stats absent.
        var publicRequest = Api_PublicProfileRequest()
        publicRequest.handle = handle
        (status, body) = try await post("social/profile/public", token: tokenB, message: publicRequest)
        XCTAssertEqual(status, 200)
        let publicProfile = try Api_PublicProfileResponse(serializedBytes: body)
        XCTAssertEqual(publicProfile.bio, "hello from the iOS e2e suite")
        XCTAssertFalse(publicProfile.hasStats_p)

        // A blocks B: mutual invisibility — B's read of A becomes not-found.
        var block = Api_BlockRequest()
        block.targetUserID = uuidB
        (status, body) = try await post("social/block", token: tokenA, message: block)
        XCTAssertEqual(status, 200)
        XCTAssertTrue(try Api_SocialAck(serializedBytes: body).success)

        (status, _) = try await post("social/profile/public", token: tokenB, message: publicRequest)
        XCTAssertEqual(status, 404)

        // Unblock restores the read.
        (status, body) = try await post("social/unblock", token: tokenA, message: block)
        XCTAssertEqual(status, 200)
        XCTAssertTrue(try Api_SocialAck(serializedBytes: body).success)

        (status, _) = try await post("social/profile/public", token: tokenB, message: publicRequest)
        XCTAssertEqual(status, 200)

        // B reports A into the triage queue.
        var report = Api_ReportRequest()
        report.targetUserID = joined.profile.userID
        report.reason = .spam
        report.context = "ios e2e report"
        (status, body) = try await post("social/report", token: tokenB, message: report)
        XCTAssertEqual(status, 200)
        XCTAssertTrue(try Api_SocialAck(serializedBytes: body).success)

        // Erase A: profile gone, handle tombstoned forever (ADR-0005).
        (status, body) = try await post("social/erase", token: tokenA, message: Api_EraseRequest())
        XCTAssertEqual(status, 200)
        XCTAssertTrue(try Api_SocialAck(serializedBytes: body).success)

        (status, _) = try await post("social/profile/get", token: tokenA, message: Api_ProfileGetRequest())
        XCTAssertEqual(status, 404)

        (status, body) = try await post("social/handle/availability", token: tokenB, message: availability)
        XCTAssertEqual(status, 200)
        availResponse = try Api_HandleAvailabilityResponse(serializedBytes: body)
        XCTAssertEqual(availResponse.status, .tombstoned)

        (status, _) = try await post("social/join", token: tokenB, message: join)
        XCTAssertEqual(status, 409, "tombstoned handles are never reissued")
    }

    // MARK: - Wire helpers (no app global state)

    private func register(email: String) async throws -> (token: String, uuid: String) {
        var request = Api_RegisterRequest()
        request.email = email
        request.password = "ios-e2e-password"
        request.scope = "mobile"
        let (status, body) = try await post("user/register", token: nil, message: request)
        XCTAssertEqual(status, 200, "register must succeed against the local backend")
        let response = try Api_RegisterResponse(serializedBytes: body)
        XCTAssertFalse(response.token.isEmpty)
        return (response.token, response.uuid)
    }

    private func post(_ path: String, token: String?, message: any SwiftProtobuf.Message) async throws -> (Int, Data) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.httpBody = try message.serializedData()
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.addValue("application/octet-stream", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return (status, data)
    }
}
