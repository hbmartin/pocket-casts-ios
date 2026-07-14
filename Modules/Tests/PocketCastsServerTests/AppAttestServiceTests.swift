import CryptoKit
import Foundation
import Testing
@testable import PocketCastsServer
@testable import PocketCastsUtils

/// Unit tests for the client half of the App Attest contract
/// (docs/AppAttest.md §1): enrollment, per-request assertion headers, the
/// Simulator/unsupported path, the 4xx discard-and-retry budget, and
/// single-flight enrollment. Everything is injected (mock attester, mock
/// backend, in-memory keychain), so no global seams are touched.
struct AppAttestServiceTests {
    private struct StubError: Error {}

    private func makeService(backend: AppAttestBackendMock,
                             attester: AppAttestKeyServiceMock,
                             keychain: InMemoryKeychainStore) -> AppAttestService {
        AppAttestService(attester: attester, urlConnection: backend.connection, keychain: keychain)
    }

    @Test func enrollmentHappyPathMintsAssertionHeaders() async throws {
        let backend = AppAttestBackendMock()
        let attester = AppAttestKeyServiceMock()
        let keychain = InMemoryKeychainStore()
        let service = makeService(backend: backend, attester: attester, keychain: keychain)

        let body = Data("feedback-body".utf8)
        let headers = await service.assertionHeaders(forBody: body)

        // Header shape (§1.3).
        #expect(headers[AppAttestService.HeaderNames.keyId] == "key-1")
        #expect(headers[AppAttestService.HeaderNames.assertion] == Data("assertion-key-1".utf8).base64EncodedString())

        // Attestation was made over SHA256(challenge bytes) (§1.2).
        let attestCall = try #require(attester.state.withLock { $0.attestCalls.first })
        #expect(attestCall.keyId == "key-1")
        #expect(attestCall.clientDataHash == Data(SHA256.hash(data: backend.challenge)))

        // The assertion signs SHA256(body bytes) (§1.3).
        let assertionCall = try #require(attester.state.withLock { $0.assertionCalls.first })
        #expect(assertionCall.clientDataHash == Data(SHA256.hash(data: body)))

        // Enroll POST body is the documented JSON envelope.
        let enrollBody = try #require(backend.state.withLock { $0.enrollBodies.first })
        let json = try #require(try JSONSerialization.jsonObject(with: enrollBody) as? [String: Any])
        #expect(json["key_id"] as? String == "key-1")
        #expect(json["attestation"] as? String == Data("attestation-key-1".utf8).base64EncodedString())
        #expect(json["challenge"] as? String == backend.challenge.base64EncodedString())

        // keyId persisted only after the 200 — presence means enrolled.
        #expect(try keychain.string(for: AppAttestService.keyIdKeychainKey) == "key-1")
    }

    @Test func unsupportedDeviceReturnsEmptyHeadersWithoutNetwork() async throws {
        let backend = AppAttestBackendMock()
        let attester = AppAttestKeyServiceMock(supported: false)
        let service = makeService(backend: backend, attester: attester, keychain: InMemoryKeychainStore())

        let headers = await service.assertionHeaders(forBody: Data("body".utf8))

        #expect(headers.isEmpty)
        #expect(backend.state.withLock { $0.challengeCount } == 0)
        #expect(backend.state.withLock { $0.enrollBodies.isEmpty })
    }

    @Test func persistedKeySkipsEnrollment() async throws {
        let backend = AppAttestBackendMock()
        let attester = AppAttestKeyServiceMock()
        let keychain = InMemoryKeychainStore()
        keychain.save(value: "stored-key", key: AppAttestService.keyIdKeychainKey, accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
        let service = makeService(backend: backend, attester: attester, keychain: keychain)

        let headers = await service.assertionHeaders(forBody: Data("body".utf8))

        #expect(headers[AppAttestService.HeaderNames.keyId] == "stored-key")
        #expect(backend.state.withLock { $0.challengeCount } == 0)
        #expect(backend.state.withLock { $0.enrollBodies.isEmpty })
    }

    @Test func enrollment4xxDiscardsKeyThenRetriesOnceAtNextNeed() async throws {
        let backend = AppAttestBackendMock(enrollStatuses: [400, 200])
        let attester = AppAttestKeyServiceMock()
        let keychain = InMemoryKeychainStore()
        let service = makeService(backend: backend, attester: attester, keychain: keychain)

        // First need: enrollment is rejected → key discarded, request goes unattested.
        let first = await service.assertionHeaders(forBody: Data("body".utf8))
        #expect(first.isEmpty)
        #expect(try keychain.string(for: AppAttestService.keyIdKeychainKey) == nil)
        #expect(backend.state.withLock { $0.enrollBodies.count } == 1)

        // Next need: one re-enrollment from scratch with a fresh key (§1.2).
        let second = await service.assertionHeaders(forBody: Data("body".utf8))
        #expect(second[AppAttestService.HeaderNames.keyId] == "key-2")
        #expect(backend.state.withLock { $0.enrollBodies.count } == 2)
        #expect(try keychain.string(for: AppAttestService.keyIdKeychainKey) == "key-2")
    }

    @Test func enrollment4xxRetryBudgetIsOnePerSession() async throws {
        let backend = AppAttestBackendMock(enrollStatuses: [400])
        let attester = AppAttestKeyServiceMock()
        let service = makeService(backend: backend, attester: attester, keychain: InMemoryKeychainStore())

        for _ in 0 ..< 3 {
            let headers = await service.assertionHeaders(forBody: Data("body".utf8))
            #expect(headers.isEmpty)
        }

        // Initial attempt + exactly one re-enrollment; the third need stays local.
        #expect(backend.state.withLock { $0.enrollBodies.count } == 2)
        #expect(backend.state.withLock { $0.challengeCount } == 2)
    }

    @Test func transientEnrollmentFailureDoesNotBurnRetryBudget() async throws {
        let backend = AppAttestBackendMock(enrollStatuses: [500, 503, 200])
        let attester = AppAttestKeyServiceMock()
        let service = makeService(backend: backend, attester: attester, keychain: InMemoryKeychainStore())

        #expect(await service.assertionHeaders(forBody: Data("body".utf8)).isEmpty)
        #expect(await service.assertionHeaders(forBody: Data("body".utf8)).isEmpty)

        // 5xx is transient (docs/AppAttest.md §4.4): the next need retries and succeeds.
        let third = await service.assertionHeaders(forBody: Data("body".utf8))
        #expect(third[AppAttestService.HeaderNames.keyId] == "key-3")
        #expect(backend.state.withLock { $0.enrollBodies.count } == 3)
    }

    @Test func concurrentCallersShareASingleEnrollment() async throws {
        let backend = AppAttestBackendMock()
        // The generateKey delay opens a real suspension window mid-enrollment so
        // the other callers arrive while it is in flight.
        let attester = AppAttestKeyServiceMock(generateKeyDelay: .milliseconds(50))
        let service = makeService(backend: backend, attester: attester, keychain: InMemoryKeychainStore())

        let body = Data("body".utf8)
        let results = await withTaskGroup(of: [String: String].self) { group in
            for _ in 0 ..< 5 {
                group.addTask { await service.assertionHeaders(forBody: body) }
            }
            return await group.reduce(into: [[String: String]]()) { $0.append($1) }
        }

        #expect(results.count == 5)
        #expect(results.allSatisfy { $0[AppAttestService.HeaderNames.keyId] == "key-1" })
        #expect(backend.state.withLock { $0.challengeCount } == 1)
        #expect(backend.state.withLock { $0.enrollBodies.count } == 1)
        #expect(attester.state.withLock { $0.generateKeyCount } == 1)
    }

    @Test func assertionFailureReturnsEmptyHeaders() async throws {
        let backend = AppAttestBackendMock()
        let attester = AppAttestKeyServiceMock(assertionErrorToThrow: StubError())
        let service = makeService(backend: backend, attester: attester, keychain: InMemoryKeychainStore())

        let headers = await service.assertionHeaders(forBody: Data("body".utf8))

        // Enrollment succeeded, but the per-request assertion failed → send unattested.
        #expect(headers.isEmpty)
        #expect(backend.state.withLock { $0.enrollBodies.count } == 1)
    }

    @Test func attestationRejectionDiscardsKeyAndReenrollsOnce() async throws {
        let backend = AppAttestBackendMock()
        let attester = AppAttestKeyServiceMock()
        let keychain = InMemoryKeychainStore()
        let service = makeService(backend: backend, attester: attester, keychain: keychain)

        let first = await service.assertionHeaders(forBody: Data("body".utf8))
        #expect(first[AppAttestService.HeaderNames.keyId] == "key-1")

        // Server answered 401 invalid_attestation (§1.5): discard for re-enrollment.
        await service.handleAttestationRejection()
        #expect(try keychain.string(for: AppAttestService.keyIdKeychainKey) == nil)

        let second = await service.assertionHeaders(forBody: Data("body".utf8))
        #expect(second[AppAttestService.HeaderNames.keyId] == "key-2")
        #expect(backend.state.withLock { $0.enrollBodies.count } == 2)

        // A second rejection exhausts the per-session budget: no further enrollment.
        await service.handleAttestationRejection()
        let third = await service.assertionHeaders(forBody: Data("body".utf8))
        #expect(third.isEmpty)
        #expect(backend.state.withLock { $0.enrollBodies.count } == 2)
    }
}
