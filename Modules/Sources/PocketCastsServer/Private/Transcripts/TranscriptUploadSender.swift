import Foundation
import PocketCastsUtils

/// Shared wire layer for the transcript contribution endpoints
/// (docs/TranscriptContributions.md §3): gzips the serialized protobuf body,
/// attaches optional account auth and App Attest assertion headers, POSTs, and
/// maps the response onto `ContributionSendResult` for the upload queue.
final class TranscriptUploadSender: Sendable {
    typealias TokenProvider = @Sendable () async -> String?
    typealias TokenInvalidator = @Sendable () -> Void
    typealias AssertionHeadersProvider = @Sendable (Data) async -> [String: String]

    /// Backoff for the single pending item when a 429 arrives without a parseable Retry-After.
    static let defaultRateLimitDelay: TimeInterval = 60
    /// Longest 429 backoff the client will honor.
    static let maximumRateLimitDelay: TimeInterval = 1.hour
    /// Queue pause when a 503 arrives without a parseable Retry-After (docs/TranscriptContributions.md §5).
    static let defaultPauseDelay: TimeInterval = 24.hours
    /// Longest queue pause the client will honor from a Retry-After hint.
    static let maximumPauseDelay: TimeInterval = 7.days
    /// Backoff for transport errors and unexpected statuses; the queue layers
    /// its own exponential backoff on top.
    static let defaultTransientRetryDelay: TimeInterval = 60

    private let urlConnection: URLConnection
    private let tokenProvider: TokenProvider
    private let tokenInvalidator: TokenInvalidator
    private let assertionHeaders: AssertionHeadersProvider

    init(urlConnection: URLConnection,
         tokenProvider: @escaping TokenProvider = TranscriptUploadSender.defaultTokenProvider,
         tokenInvalidator: @escaping TokenInvalidator = TranscriptUploadSender.defaultTokenInvalidator,
         assertionHeaders: @escaping AssertionHeadersProvider = TranscriptUploadSender.defaultAssertionHeadersProvider) {
        self.urlConnection = urlConnection
        self.tokenProvider = tokenProvider
        self.tokenInvalidator = tokenInvalidator
        self.assertionHeaders = assertionHeaders
    }

    /// Bearer auth is optional on these endpoints (attribution only): attach a token
    /// when signed in, otherwise send anonymously — the same signed-in check the
    /// feedback task uses to pick its authenticated variant.
    static let defaultTokenProvider: TokenProvider = {
        guard SyncManager.isUserLoggedIn() else { return nil }
        if let token = ServerSettings.validSyncingV2Token() {
            return token
        }
        // acquireToken() performs blocking network I/O; keep it off the cooperative pool.
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: TokenHelper.shared.acquireToken())
            }
        }
    }

    static let defaultTokenInvalidator: TokenInvalidator = {
        KeychainHelper.removeKey(ServerConstants.Values.syncingV2TokenKey)
        ServerSettings.setTokenExpiryDate(nil)
    }

    /// Assertion headers sign the exact body bytes on the wire (docs/AppAttest.md §1.3),
    /// i.e. the gzipped payload. Returns [:] when attestation is unavailable
    /// (Simulator, unsupported devices) — the request is then sent unattested.
    static let defaultAssertionHeadersProvider: AssertionHeadersProvider = { body in
        await AppAttestService.shared.assertionHeaders(forBody: body)
    }

    /// Serializes nothing itself: callers pass the already-serialized protobuf
    /// message; this gzips it and performs the POST.
    func post(messageData: Data, to urlString: String) async -> ContributionSendResult {
        let body: Data
        do {
            body = try GzipCoder.gzip(messageData)
        } catch {
            return .permanentFailure("Failed to gzip request body: \(error)")
        }

        guard let url = URL(string: urlString) else {
            return .permanentFailure("Invalid endpoint URL: \(urlString)")
        }

        let token = await tokenProvider()
        let firstAttempt = await performPost(body: body, to: url, token: token)
        guard let firstResponse = firstAttempt.response else {
            return .retryAfter(Self.defaultTransientRetryDelay)
        }

        // Account auth is attribution-only for these endpoints. If a locally
        // valid token is rejected, invalidate it and retry once anonymously.
        // performPost mints a fresh assertion for the second request, so strict
        // App Attest counters never see a replayed assertion.
        if token != nil,
           firstResponse.statusCode == ServerConstants.HttpConstants.unauthorized,
           !Self.isInvalidAttestation(firstAttempt.data) {
            tokenInvalidator()
            let anonymousAttempt = await performPost(body: body, to: url, token: nil)
            guard let anonymousResponse = anonymousAttempt.response else {
                return .retryAfter(Self.defaultTransientRetryDelay)
            }
            return Self.result(for: anonymousResponse, body: anonymousAttempt.data)
        }

        return Self.result(for: firstResponse, body: firstAttempt.data)
    }

    private func performPost(body: Data, to url: URL, token: String?) async -> (data: Data?, response: HTTPURLResponse?) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: ServerConstants.Timeouts.general)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/octet-stream", forHTTPHeaderField: ServerConstants.HttpHeaders.contentType)
        request.addValue("application/octet-stream", forHTTPHeaderField: ServerConstants.HttpHeaders.accept)
        request.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
        request.addLocalizationHeaders()
        request.setValue(ServerConfig.shared.syncDelegate?.privateUserAgent() ?? "", forHTTPHeaderField: ServerConstants.HttpHeaders.userAgent)

        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: ServerConstants.HttpHeaders.authorization)
        }
        for (field, value) in await assertionHeaders(body) {
            request.setValue(value, forHTTPHeaderField: field)
        }

        do {
            let (data, response) = try await urlConnection.send(request: request)
            return (data, response as? HTTPURLResponse)
        } catch {
            FileLog.shared.addMessage("TranscriptUploadSender: POST to \(url.absoluteString) failed: \(error)")
            return (nil, nil)
        }
    }

    /// Maps a response onto the queue's result contract (docs/TranscriptContributions.md §5).
    static func result(for response: HTTPURLResponse, body: Data?) -> ContributionSendResult {
        switch response.statusCode {
        case ServerConstants.HttpConstants.ok, ServerConstants.HttpConstants.accepted:
            return .accepted
        case ServerConstants.HttpConstants.tooManyRequests:
            return .retryAfter(response.retryAfterInterval(maximum: maximumRateLimitDelay) ?? defaultRateLimitDelay)
        case ServerConstants.HttpConstants.serviceUnavailable:
            return .pauseQueue(response.retryAfterInterval(maximum: maximumPauseDelay) ?? defaultPauseDelay)
        case ServerConstants.HttpConstants.unauthorized where isInvalidAttestation(body):
            return .attestationRejected
        case ServerConstants.HttpConstants.unauthorized:
            // No Bearer was available, or the one anonymous retry was still
            // unauthorized. Keep the durable row for a later attempt.
            return .retryAfter(defaultTransientRetryDelay)
        case ServerConstants.HttpConstants.conflict where isStaleAttestation(body):
            // A valid lower counter arrived after a newer assertion. Retry with
            // a fresh assertion; the enrolled key itself remains healthy.
            return .retryAfter(defaultTransientRetryDelay)
        case ServerConstants.HttpConstants.badRequest, ServerConstants.HttpConstants.unprocessableEntity:
            return .permanentFailure("HTTP \(response.statusCode)\(serverMessageSuffix(from: body))")
        default:
            return .retryAfter(defaultTransientRetryDelay)
        }
    }

    /// Detects the `401 {"errorMessageId":"invalid_attestation"}` envelope (docs/AppAttest.md §1.5).
    private static func isInvalidAttestation(_ body: Data?) -> Bool {
        errorMessageId(from: body) == AppAttestService.invalidAttestationErrorId
    }

    private static func isStaleAttestation(_ body: Data?) -> Bool {
        errorMessageId(from: body) == AppAttestService.staleAttestationErrorId
    }

    private static func errorMessageId(from body: Data?) -> String? {
        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let errorMessageId = json["errorMessageId"] as? String
        else {
            return nil
        }
        return errorMessageId
    }

    private static func serverMessageSuffix(from body: Data?) -> String {
        guard let body, !body.isEmpty, let message = String(data: body, encoding: .utf8), !message.isEmpty else {
            return ""
        }
        return ": \(message.prefix(200))"
    }
}
