import Foundation
import PocketCastsUtils

/// Shared wire layer for the transcript contribution endpoints
/// (docs/TranscriptContributions.md §3): gzips the serialized protobuf body,
/// attaches optional account auth, POSTs, and maps the response onto
/// `ContributionSendResult` for the upload queue.
///
/// App Attest signing is NOT done here: `URLConnection` routes these endpoints
/// through `AppAttestService.send`, which signs the canonical request, retries
/// a stale counter or invalid assertion once, and otherwise throws
/// `AppAttestTransportError` — surfaced by this sender as
/// `.attestationRejected` so the queue parks with backoff (docs/AppAttest.md §1.5).
final class TranscriptUploadSender: Sendable {
    typealias TokenProvider = @Sendable () async -> String?
    typealias TokenInvalidator = @Sendable () -> Void

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

    init(urlConnection: URLConnection,
         tokenProvider: @escaping TokenProvider = TranscriptUploadSender.defaultTokenProvider,
         tokenInvalidator: @escaping TokenInvalidator = TranscriptUploadSender.defaultTokenInvalidator) {
        self.urlConnection = urlConnection
        self.tokenProvider = tokenProvider
        self.tokenInvalidator = tokenInvalidator
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

        // Only the contribution endpoint answers a 2xx with a receipt. Parsing
        // it for other endpoints could misread an unrelated body as a receipt
        // and route a non-contribution row into the metadata pipeline.
        let expectsReceipt = urlString == ServerConstants.Urls.transcriptContributeUrl

        let token = await tokenProvider()
        switch await performPost(body: body, to: url, token: token) {
        case .attestationRejected:
            return .attestationRejected
        case .transportFailure:
            return .retryAfter(Self.defaultTransientRetryDelay)
        case .response(let data, let response):
            // Account auth is attribution-only for these endpoints. If a locally
            // valid token is rejected, invalidate it and retry once anonymously.
            // The attested transport mints a fresh assertion for the second
            // request, so strict App Attest counters never see a replayed assertion.
            if token != nil,
               response.statusCode == ServerConstants.HttpConstants.unauthorized,
               !Self.isInvalidAttestation(data) {
                tokenInvalidator()
                switch await performPost(body: body, to: url, token: nil) {
                case .attestationRejected:
                    return .attestationRejected
                case .transportFailure:
                    return .retryAfter(Self.defaultTransientRetryDelay)
                case .response(let anonymousData, let anonymousResponse):
                    return Self.result(for: anonymousResponse, body: anonymousData, expectsContributionReceipt: expectsReceipt)
                }
            }
            return Self.result(for: response, body: data, expectsContributionReceipt: expectsReceipt)
        }
    }

    private enum PostAttemptOutcome {
        case response(data: Data?, response: HTTPURLResponse)
        /// The central App Attest transport gave up (docs/AppAttest.md §1.5):
        /// it already retried a stale counter / re-enrolled an invalid key once.
        case attestationRejected
        case transportFailure
    }

    private func performPost(body: Data, to url: URL, token: String?) async -> PostAttemptOutcome {
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
        do {
            let (data, response) = try await urlConnection.send(request: request)
            guard let httpResponse = response as? HTTPURLResponse else { return .transportFailure }
            return .response(data: data, response: httpResponse)
        } catch let error as AppAttestTransportError {
            FileLog.shared.addMessage("TranscriptUploadSender: POST to \(url.absoluteString) rejected by App Attest: \(error)")
            return .attestationRejected
        } catch {
            FileLog.shared.addMessage("TranscriptUploadSender: POST to \(url.absoluteString) failed: \(error)")
            return .transportFailure
        }
    }

    /// Maps a response onto the queue's result contract (docs/TranscriptContributions.md §5).
    /// `expectsContributionReceipt` is true only for the contribution endpoint,
    /// whose 2xx body carries the candidateID + one-time attachment token receipt.
    static func result(for response: HTTPURLResponse, body: Data?, expectsContributionReceipt: Bool = false) -> ContributionSendResult {
        switch response.statusCode {
        case ServerConstants.HttpConstants.ok, ServerConstants.HttpConstants.accepted:
            if expectsContributionReceipt,
               let body,
               let receipt = try? Api_TranscriptContributionResponse(serializedBytes: body),
               !receipt.candidateID.isEmpty,
               !receipt.attachmentToken.isEmpty {
                return .acceptedContribution(TranscriptContributionReceipt(
                    candidateID: receipt.candidateID,
                    sha256: receipt.sha256,
                    attachmentToken: receipt.attachmentToken
                ))
            }
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

    /// Maps a `POST transcripts/contribute/metadata` response onto the queue's
    /// result contract. Unlike the contribution/sighting mapping, the attachment
    /// token is one-time and candidate-scoped: any 4xx other than auth (401),
    /// timeout (408) or rate limiting (429) means the token is consumed/expired
    /// and the identical attachment can never succeed again.
    static func metadataResult(for response: HTTPURLResponse, body: Data?) -> ContributionSendResult {
        switch response.statusCode {
        case 200 ..< 300:
            return .accepted
        case ServerConstants.HttpConstants.tooManyRequests:
            return .retryAfter(response.retryAfterInterval(maximum: maximumRateLimitDelay) ?? defaultRateLimitDelay)
        case ServerConstants.HttpConstants.serviceUnavailable:
            return .pauseQueue(response.retryAfterInterval(maximum: maximumPauseDelay) ?? defaultPauseDelay)
        case ServerConstants.HttpConstants.unauthorized where isInvalidAttestation(body):
            return .attestationRejected
        case ServerConstants.HttpConstants.unauthorized, 408:
            // Stale bearer or request timeout; the durable row retries later.
            return .retryAfter(defaultTransientRetryDelay)
        case ServerConstants.HttpConstants.conflict where isStaleAttestation(body):
            return .retryAfter(defaultTransientRetryDelay)
        case 400 ..< 500:
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

public extension CorpusMetadataAttachmentClient {
    /// Queue-facing variant of `attach(_:)`: same request, but the response is
    /// classified onto `ContributionSendResult` so the durable metadata job can
    /// tell transient failures apart from a consumed/expired one-time attachment
    /// token (4xx), which can never succeed again with the same candidate.
    static func attachResult(_ metadata: CorpusMetadataAttachment,
                             connection: URLConnection = URLConnection(handler: URLSession.shared)) async -> ContributionSendResult {
        guard let url = URL(string: ServerConstants.Urls.api() + "transcripts/contribute/metadata"),
              let body = try? JSONEncoder().encode(metadata), body.count <= 128 * 1024
        else {
            return .permanentFailure("Metadata attachment body invalid or over the 128 KiB cap")
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: ServerConstants.Timeouts.general)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: ServerConstants.HttpHeaders.contentType)
        request.setValue("application/json", forHTTPHeaderField: ServerConstants.HttpHeaders.accept)
        do {
            let (data, response) = try await connection.send(request: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .retryAfter(TranscriptUploadSender.defaultTransientRetryDelay)
            }
            return TranscriptUploadSender.metadataResult(for: httpResponse, body: data)
        } catch let error as AppAttestTransportError {
            FileLog.shared.addMessage("CorpusMetadataAttachmentClient: metadata POST rejected by App Attest: \(error)")
            return .attestationRejected
        } catch {
            FileLog.shared.addMessage("CorpusMetadataAttachmentClient: metadata POST failed: \(error)")
            return .retryAfter(TranscriptUploadSender.defaultTransientRetryDelay)
        }
    }
}
