import CryptoKit
import Foundation
import PocketCastsUtils

/// Client side of the App Attest contract (docs/AppAttest.md §1): owns the
/// per-install DeviceCheck key, lazily enrolls it with the fork backend, and
/// mints per-request assertion headers over the exact request body bytes.
///
/// Usage (best-effort — an empty dictionary means "send unattested"; whether
/// that is accepted is server policy, never a client secret):
///
///     let headers = await AppAttestService.shared.assertionHeaders(forBody: bodyData)
///     headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
///
/// On a `401 {"errorMessageId":"invalid_attestation"}` response, callers must
/// `await AppAttestService.shared.handleAttestationRejection()` (which discards
/// the key so the next request re-enrolls once per session) and park their
/// queue with backoff (§1.5).
///
/// The actor serializes all key lifecycle transitions, and enrollment is
/// single-flight: concurrent header requests share one in-flight enrollment.
/// All attestation must go through this type — direct `DCAppAttestService` use
/// elsewhere is flagged by the `pocketcasts.app-attest-single-owner` Semgrep rule.
public actor AppAttestService {
    public static let shared = AppAttestService()

    /// Header names attested requests carry (docs/AppAttest.md §1.3).
    public enum HeaderNames {
        public static let keyId = "X-Attest-Key-Id"
        public static let assertion = "X-Attest-Assertion"
    }

    /// The `errorMessageId` of the 401 the backend returns when assertion
    /// verification fails (docs/AppAttest.md §1.5).
    public static let invalidAttestationErrorId = "invalid_attestation"

    /// Keychain account for the enrolled keyId. Written only after the backend
    /// confirms enrollment, so presence == enrolled. `ThisDeviceOnly` so the key
    /// never migrates via backup; a restored device simply re-enrolls (§1.1).
    static let keyIdKeychainKey = "PCAppAttestKeyId"

    /// Bootstrap endpoints live on the api host family — the same base as the
    /// feedback endpoint this contract first protects (docs/AppAttest.md §1.2).
    enum Endpoints {
        static var challenge: String { ServerConstants.Urls.api() + "attest/challenge" }
        static var enroll: String { ServerConstants.Urls.api() + "attest/enroll" }
    }

    private let attester: AppAttestKeyService
    private let urlConnection: URLConnection
    private let keychain: KeychainStoring
    private let requestTimeout: TimeInterval = 30

    /// Set once enrollment is confirmed (or a persisted keyId is read back).
    private var cachedKeyId: String?

    /// Single-flight gate: concurrent callers needing enrollment await this
    /// task instead of racing their own.
    private var inFlightEnrollment: Task<String?, Never>?

    /// §1.2/§1.5: after a key discard (enrollment 4xx or a server rejection) at
    /// most one re-enrollment is attempted per app session; once the budget is
    /// spent, callers send unattested until the next launch.
    private var keyWasDiscarded = false
    private var reEnrollmentsRemaining = 1

    init(attester: AppAttestKeyService = DeviceCheckAppAttestAdapter(),
         urlConnection: URLConnection = URLConnection(handler: URLSession.shared),
         keychain: KeychainStoring = KeychainHelper.store) {
        self.attester = attester
        self.urlConnection = urlConnection
        self.keychain = keychain
    }

    // MARK: - Public API

    /// Returns the App Attest headers for a request whose body is exactly
    /// `body` (the assertion signs those bytes — they must be sent unmodified).
    ///
    /// Returns `[:]` when attestation is unsupported (Simulator/dev builds) or
    /// on unrecoverable failure; callers send the request unattested and the
    /// server's per-endpoint enforcement mode decides. Enrollment happens
    /// lazily inside this call when the install has no enrolled key yet.
    public func assertionHeaders(forBody body: Data) async -> [String: String] {
        guard attester.isSupported else { return [:] }
        guard let keyId = await enrolledKeyId() else { return [:] }

        do {
            let assertion = try await attester.generateAssertion(keyId, clientDataHash: Data(SHA256.hash(data: body)))
            return [
                HeaderNames.keyId: keyId,
                HeaderNames.assertion: assertion.base64EncodedString()
            ]
        } catch {
            // Unrecoverable for this request; send unattested. If the key itself is
            // bad the server's 401 → handleAttestationRejection() path recovers it.
            FileLog.shared.addMessage("AppAttestService: generateAssertion failed: \(error)")
            return [:]
        }
    }

    /// Call when the server answers `401 invalid_attestation` (see
    /// `invalidAttestationErrorId`): discards the local key so the next
    /// `assertionHeaders(forBody:)` re-enrolls from scratch — bounded to one
    /// re-enrollment per app session (docs/AppAttest.md §1.5). The caller owns
    /// parking its queue with backoff; this never surfaces to the user.
    public func handleAttestationRejection() {
        FileLog.shared.addMessage("AppAttestService: server rejected an assertion; discarding key for re-enrollment")
        discardKey()
    }

    // MARK: - Key lifecycle

    private func enrolledKeyId() async -> String? {
        if let cachedKeyId { return cachedKeyId }
        if let inFlightEnrollment { return await inFlightEnrollment.value }

        // The keyId is persisted only after the backend confirms enrollment,
        // so a stored value means this install is already enrolled.
        if let stored = ((try? keychain.string(for: Self.keyIdKeychainKey)) ?? nil), !stored.isEmpty {
            cachedKeyId = stored
            return stored
        }

        guard !keyWasDiscarded || reEnrollmentsRemaining > 0 else { return nil }
        if keyWasDiscarded { reEnrollmentsRemaining -= 1 }

        // No suspension between the in-flight check above and this assignment,
        // so concurrent callers cannot start a second enrollment.
        let enrollment = Task { await self.performEnrollment() }
        inFlightEnrollment = enrollment
        let keyId = await enrollment.value
        inFlightEnrollment = nil
        return keyId
    }

    private func discardKey() {
        cachedKeyId = nil
        keychain.save(value: nil, key: Self.keyIdKeychainKey, accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
        keyWasDiscarded = true
    }

    // MARK: - Enrollment (docs/AppAttest.md §1.2)

    private func performEnrollment() async -> String? {
        do {
            guard let challenge = try await fetchChallenge() else { return nil }

            let keyId = try await attester.generateKey()
            let clientDataHash = Data(SHA256.hash(data: challenge.bytes))
            let attestation = try await attester.attestKey(keyId, clientDataHash: clientDataHash)
            let statusCode = try await postEnrollment(keyId: keyId, attestation: attestation, challengeBase64: challenge.base64)

            switch statusCode {
            case ServerConstants.HttpConstants.ok:
                keychain.save(value: keyId, key: Self.keyIdKeychainKey, accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
                cachedKeyId = keyId
                FileLog.shared.addMessage("AppAttestService: enrolled App Attest key")
                return keyId
            case 400 ..< 500:
                // The server refused this key/attestation: discard it and allow one
                // enrollment from scratch at the next need this session (§1.2).
                FileLog.shared.addMessage("AppAttestService: enrollment rejected with status \(statusCode); discarding key")
                discardKey()
                return nil
            default:
                // Transient (5xx or transport-shaped): keep the key budget intact and
                // retry at the next need. The just-generated key goes dormant; a fresh
                // one is generated next attempt.
                FileLog.shared.addMessage("AppAttestService: enrollment failed with status \(statusCode); will retry at next need")
                return nil
            }
        } catch {
            FileLog.shared.addMessage("AppAttestService: enrollment error: \(error)")
            return nil
        }
    }

    private struct ChallengeResponse: Decodable {
        let challenge: String
    }

    private func fetchChallenge() async throws -> (base64: String, bytes: Data)? {
        guard let url = URL(string: Endpoints.challenge) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: requestTimeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: ServerConstants.HttpHeaders.accept)

        let (data, response) = try await urlConnection.send(request: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == ServerConstants.HttpConstants.ok, let data else {
            FileLog.shared.addMessage("AppAttestService: challenge fetch failed (status \((response as? HTTPURLResponse)?.statusCode ?? -1))")
            return nil
        }

        let parsed = try JSONDecoder().decode(ChallengeResponse.self, from: data)
        guard let bytes = Data(base64Encoded: parsed.challenge) else {
            FileLog.shared.addMessage("AppAttestService: challenge was not valid base64")
            return nil
        }
        return (parsed.challenge, bytes)
    }

    private struct EnrollmentRequestBody: Encodable {
        let keyId: String
        let attestation: String
        let challenge: String

        enum CodingKeys: String, CodingKey {
            case keyId = "key_id"
            case attestation
            case challenge
        }
    }

    /// Returns the HTTP status of the enroll POST.
    private func postEnrollment(keyId: String, attestation: Data, challengeBase64: String) async throws -> Int {
        guard let url = URL(string: Endpoints.enroll) else { return ServerConstants.HttpConstants.serverError }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: ServerConstants.HttpHeaders.contentType)
        request.setValue("application/json", forHTTPHeaderField: ServerConstants.HttpHeaders.accept)
        request.httpBody = try JSONEncoder().encode(EnrollmentRequestBody(keyId: keyId, attestation: attestation.base64EncodedString(), challenge: challengeBase64))

        let (_, response) = try await urlConnection.send(request: request)
        guard let httpResponse = response as? HTTPURLResponse else { return ServerConstants.HttpConstants.serverError }
        return httpResponse.statusCode
    }
}
