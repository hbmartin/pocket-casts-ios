import Foundation
import PocketCastsUtils
import SwiftProtobuf
import Synchronization
import Testing

@testable import PocketCastsServer

/// Wire-layer tests for the transcript contribution tasks
/// (docs/TranscriptContributions.md §3): gzipped protobuf bodies, optional
/// Bearer auth, and the response-to-`ContributionSendResult` mapping the
/// upload queue consumes. App Attest signing belongs to the central transport
/// (`URLConnection` → `AppAttestService`), never to the sender itself; its
/// `AppAttestTransportError` surfaces as `.attestationRejected`.
@Suite("TranscriptUploadTasks")
struct TranscriptUploadTaskTests {
    // MARK: - Fixtures

    private static func contribution() -> TranscriptContributionPayload {
        TranscriptContributionPayload(
            episodeUuid: "episode-uuid-1",
            podcastUuid: "podcast-uuid-1",
            gzippedVtt: Data([0x1f, 0x8b, 0x01, 0x02, 0x03]),
            gzippedFingerprint: Data([0x1f, 0x8b, 0x0a, 0x0b]),
            engine: "whisperkit",
            modelId: "whisper-large-v3-turbo",
            language: "en-US",
            diarized: true,
            appVersion: "7.87",
            episodeDurationSeconds: 1234.5,
            createdAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
    }

    private static func sighting() -> TranscriptSightingPayload {
        TranscriptSightingPayload(
            episodeUuid: "episode-uuid-2",
            podcastUuid: "podcast-uuid-2",
            transcriptUrl: "https://example.com/transcript.vtt",
            format: "text/vtt",
            language: nil
        )
    }

    private static func metadataAttachment() -> CorpusMetadataAttachment {
        CorpusMetadataAttachment(
            candidateID: "cand-1",
            attachmentToken: "token-1",
            summary: "A factual summary.",
            chapters: [CorpusMetadataAttachment.Chapter(title: "Intro", timestamp: "00:00", startTime: 0)]
        )
    }

    /// Serialized `Api_TranscriptContributionResponse` receipt bytes, as the
    /// contribution endpoint returns them on a 2xx.
    private static func receiptBody() throws -> Data {
        var receipt = Api_TranscriptContributionResponse()
        receipt.candidateID = "cand-1"
        receipt.sha256 = "sha-1"
        receipt.attachmentToken = "token-1"
        return try receipt.serializedData()
    }

    private static func httpResponse(status: Int, headers: [String: String]? = nil) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://api.pocketcasts.com/transcripts/contribute")!,
                        statusCode: status,
                        httpVersion: nil,
                        headerFields: headers)!
    }

    /// A sender whose transport captures the outgoing request and answers with a
    /// canned status; the token provider is an injectable stub.
    private static func makeSender(status: Int = 202,
                                   responseHeaders: [String: String]? = nil,
                                   responseBody: Data = Data(),
                                   token: String? = nil,
                                   tokenInvalidator: @escaping TranscriptUploadSender.TokenInvalidator = {},
                                   capturedRequest: UncheckedSendableBox<URLRequest?> = .init(nil)) -> TranscriptUploadSender {
        let connection = URLConnection(mockHandler: { request in
            capturedRequest.value = request
            return (responseBody, Self.httpResponse(status: status, headers: responseHeaders))
        })
        return TranscriptUploadSender(urlConnection: connection,
                                      tokenProvider: { token },
                                      tokenInvalidator: tokenInvalidator)
    }

    // MARK: - Body encoding

    @Test("contribution body is valid gzip of a decodable proto, with the right headers and endpoint")
    func contributionBodyIsGzippedProto() async throws {
        let captured = UncheckedSendableBox<URLRequest?>(nil)
        let task = TranscriptContributeTask(sender: Self.makeSender(capturedRequest: captured))
        let payload = Self.contribution()

        let result = await task.send(payload)

        #expect(result == .accepted)
        let request = try #require(captured.value)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString.hasSuffix("transcripts/contribute") == true)
        #expect(request.value(forHTTPHeaderField: "Content-Encoding") == "gzip")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")

        let body = try #require(request.httpBody)
        #expect(body.prefix(2) == Data([0x1f, 0x8b]), "body must be a gzip stream")

        let message = try Api_TranscriptContributionRequest(serializedBytes: GzipCoder.gunzip(body))
        #expect(message.episodeUuid == payload.episodeUuid)
        #expect(message.podcastUuid == payload.podcastUuid)
        #expect(message.vtt == payload.gzippedVtt)
        #expect(message.fingerprint == payload.gzippedFingerprint)
        #expect(message.engine == payload.engine)
        #expect(message.modelID == payload.modelId)
        #expect(message.language == payload.language)
        #expect(message.diarized == payload.diarized)
        #expect(message.appVersion == payload.appVersion)
        #expect(message.episodeDurationSeconds == payload.episodeDurationSeconds)
        #expect(message.createdAt.date == payload.createdAt)
    }

    @Test("sighting body is valid gzip of a decodable proto posted to the sighting endpoint")
    func sightingBodyIsGzippedProto() async throws {
        let captured = UncheckedSendableBox<URLRequest?>(nil)
        let task = TranscriptSightingTask(sender: Self.makeSender(capturedRequest: captured))
        let payload = Self.sighting()

        let result = await task.send(payload)

        #expect(result == .accepted)
        let request = try #require(captured.value)
        #expect(request.url?.absoluteString.hasSuffix("transcripts/sighting") == true)
        #expect(request.value(forHTTPHeaderField: "Content-Encoding") == "gzip")

        let body = try #require(request.httpBody)
        let message = try Api_TranscriptSightingRequest(serializedBytes: GzipCoder.gunzip(body))
        #expect(message.episodeUuid == payload.episodeUuid)
        #expect(message.podcastUuid == payload.podcastUuid)
        #expect(message.transcriptURL == payload.transcriptUrl)
        #expect(message.format == payload.format)
        #expect(message.language.isEmpty, "nil language travels as the proto3 empty string")
    }

    // MARK: - Auth headers

    @Test("bearer token is attached when the token provider has one")
    func bearerAttachedWhenSignedIn() async throws {
        let captured = UncheckedSendableBox<URLRequest?>(nil)
        let task = TranscriptSightingTask(sender: Self.makeSender(token: "token-abc", capturedRequest: captured))

        _ = await task.send(Self.sighting())

        let request = try #require(captured.value)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-abc")
    }

    @Test("no Authorization header when signed out")
    func bearerAbsentWhenSignedOut() async throws {
        let captured = UncheckedSendableBox<URLRequest?>(nil)
        let task = TranscriptSightingTask(sender: Self.makeSender(token: nil, capturedRequest: captured))

        _ = await task.send(Self.sighting())

        let request = try #require(captured.value)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("a rejected bearer is invalidated and retried once anonymously, with no sender-attached attest headers")
    func rejectedBearerRetriesAnonymously() async throws {
        let requests = Mutex<[URLRequest]>([])
        let statuses = Mutex([401, 202])
        let invalidated = Mutex(false)
        let connection = URLConnection(mockHandler: { request in
            requests.withLock { $0.append(request) }
            let status = statuses.withLock { values in values.removeFirst() }
            return (Data(), Self.httpResponse(status: status))
        })
        let sender = TranscriptUploadSender(
            urlConnection: connection,
            tokenProvider: { "stale-token" },
            tokenInvalidator: { invalidated.withLock { $0 = true } }
        )

        let result = await TranscriptSightingTask(sender: sender).send(Self.sighting())

        #expect(result == .accepted)
        #expect(invalidated.withLock { $0 })
        let captured = requests.withLock { $0 }
        #expect(captured.count == 2)
        #expect(captured[0].value(forHTTPHeaderField: "Authorization") == "Bearer stale-token")
        #expect(captured[1].value(forHTTPHeaderField: "Authorization") == nil)
        // App Attest signing happens in the central transport, downstream of the
        // sender: neither attempt may carry sender-attached attest headers.
        for request in captured {
            #expect(request.value(forHTTPHeaderField: AppAttestService.HeaderNames.keyId) == nil)
            #expect(request.value(forHTTPHeaderField: AppAttestService.HeaderNames.assertion) == nil)
        }
    }

    @Test("App Attest transport errors surface as attestationRejected so the queue parks with backoff")
    func attestTransportErrorMapsToAttestationRejected() async {
        // AppAttestService.send has already retried a stale counter / invalid
        // assertion once by the time it throws; the sender must park, not loop.
        let connection = URLConnection(mockHandler: { _ in
            throw AppAttestTransportError.invalidAssertion
        })
        let sender = TranscriptUploadSender(urlConnection: connection, tokenProvider: { nil })

        let result = await TranscriptContributeTask(sender: sender).send(Self.contribution())

        #expect(result == .attestationRejected)
    }

    // MARK: - Contribution receipt

    @Test("a contribution 2xx with a receipt body maps to acceptedContribution")
    func contributionReceiptParsed() async throws {
        let receiptBody = try Self.receiptBody()

        let result = await TranscriptContributeTask(sender: Self.makeSender(responseBody: receiptBody))
            .send(Self.contribution())

        #expect(result == .acceptedContribution(TranscriptContributionReceipt(
            candidateID: "cand-1",
            sha256: "sha-1",
            attachmentToken: "token-1"
        )))
    }

    @Test("a sighting 2xx never parses a contribution receipt, even from receipt-shaped bytes")
    func sightingIgnoresReceiptShapedBody() async throws {
        let receiptBody = try Self.receiptBody()

        let result = await TranscriptSightingTask(sender: Self.makeSender(responseBody: receiptBody))
            .send(Self.sighting())

        #expect(result == .accepted, "Only the contribution endpoint returns a receipt; a sighting row must not enter the metadata pipeline")
    }

    // MARK: - Response mapping

    @Test("2xx acknowledgements map to accepted", arguments: [200, 202])
    func successStatuses(status: Int) {
        #expect(TranscriptUploadSender.result(for: Self.httpResponse(status: status), body: nil) == .accepted)
    }

    @Test("429 honors Retry-After in delay-seconds form")
    func rateLimitedWithSeconds() {
        let response = Self.httpResponse(status: 429, headers: ["Retry-After": "120"])
        #expect(TranscriptUploadSender.result(for: response, body: nil) == .retryAfter(120))
    }

    @Test("429 honors Retry-After in HTTP-date form")
    func rateLimitedWithHTTPDate() throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let header = formatter.string(from: Date(timeIntervalSinceNow: 90))

        let response = Self.httpResponse(status: 429, headers: ["Retry-After": header])
        guard case .retryAfter(let delay) = TranscriptUploadSender.result(for: response, body: nil) else {
            Issue.record("expected retryAfter")
            return
        }
        // The formatter truncates to whole seconds and a moment passes before parsing.
        #expect(delay > 80 && delay <= 90)
    }

    @Test("429 without Retry-After uses the default rate-limit backoff")
    func rateLimitedWithoutHeader() {
        let response = Self.httpResponse(status: 429)
        #expect(TranscriptUploadSender.result(for: response, body: nil) == .retryAfter(TranscriptUploadSender.defaultRateLimitDelay))
    }

    @Test("503 parks the queue for the Retry-After window")
    func pauseWithRetryAfter() {
        let response = Self.httpResponse(status: 503, headers: ["Retry-After": "3600"])
        #expect(TranscriptUploadSender.result(for: response, body: nil) == .pauseQueue(3600))
    }

    @Test("503 without Retry-After parks the queue for the default 24h")
    func pauseWithoutHeader() {
        let response = Self.httpResponse(status: 503)
        #expect(TranscriptUploadSender.result(for: response, body: nil) == .pauseQueue(24.hours))
    }

    @Test("401 invalid_attestation maps to attestationRejected")
    func invalidAttestation() {
        let body = Data(#"{"errorMessageId":"invalid_attestation"}"#.utf8)
        #expect(TranscriptUploadSender.result(for: Self.httpResponse(status: 401), body: body) == .attestationRejected)
    }

    @Test("409 stale_attestation retries without rejecting the enrolled key")
    func staleAttestation() {
        let body = Data(#"{"errorMessageId":"stale_attestation"}"#.utf8)
        let result = TranscriptUploadSender.result(for: Self.httpResponse(status: 409), body: body)
        #expect(result == .retryAfter(TranscriptUploadSender.defaultTransientRetryDelay))
    }

    @Test("401 without the attestation envelope is transient (stale bearer)")
    func plainUnauthorizedIsTransient() {
        let body = Data(#"{"errorMessageId":"token_expired"}"#.utf8)
        let result = TranscriptUploadSender.result(for: Self.httpResponse(status: 401), body: body)
        #expect(result == .retryAfter(TranscriptUploadSender.defaultTransientRetryDelay))
    }

    @Test("validation rejections are permanent", arguments: [400, 422])
    func permanentFailures(status: Int) {
        let result = TranscriptUploadSender.result(for: Self.httpResponse(status: status), body: Data("bad vtt".utf8))
        guard case .permanentFailure(let reason) = result else {
            Issue.record("expected permanentFailure, got \(result)")
            return
        }
        #expect(reason.contains("\(status)"))
        #expect(reason.contains("bad vtt"))
    }

    @Test("transport errors surface as a transient retry")
    func transportErrorIsTransient() async {
        let connection = URLConnection(mockHandler: { _ in
            throw URLError(.notConnectedToInternet)
        })
        let sender = TranscriptUploadSender(urlConnection: connection,
                                            tokenProvider: { nil })
        let task = TranscriptContributeTask(sender: sender)

        let result = await task.send(Self.contribution())

        #expect(result == .retryAfter(TranscriptUploadSender.defaultTransientRetryDelay))
    }

    // MARK: - Metadata attachment

    @Test("metadata attachment 2xx maps to accepted", arguments: [200, 204])
    func metadataAttachAccepted(status: Int) async {
        let connection = URLConnection(mockHandler: { _ in (Data(), Self.httpResponse(status: status)) })

        let result = await CorpusMetadataAttachmentClient.attachResult(Self.metadataAttachment(), connection: connection)

        #expect(result == .accepted)
    }

    @Test("a consumed/expired one-time attachment token is permanent", arguments: [400, 403, 404, 409, 410, 422])
    func metadataPermanent4xx(status: Int) async {
        let connection = URLConnection(mockHandler: { _ in
            (Data("token consumed".utf8), Self.httpResponse(status: status))
        })

        let result = await CorpusMetadataAttachmentClient.attachResult(Self.metadataAttachment(), connection: connection)

        guard case .permanentFailure(let reason) = result else {
            Issue.record("expected permanentFailure, got \(result)")
            return
        }
        #expect(reason.contains("\(status)"))
    }

    @Test("metadata auth, timeout and rate-limit responses stay transient", arguments: [401, 408, 429])
    func metadataTransientStatuses(status: Int) async {
        let connection = URLConnection(mockHandler: { _ in (Data(), Self.httpResponse(status: status)) })

        let result = await CorpusMetadataAttachmentClient.attachResult(Self.metadataAttachment(), connection: connection)

        guard case .retryAfter = result else {
            Issue.record("expected retryAfter, got \(result)")
            return
        }
    }

    @Test("metadata 401 invalid_attestation and App Attest transport errors both reject the attestation")
    func metadataAttestationRejection() async {
        let envelope = URLConnection(mockHandler: { _ in
            (Data(#"{"errorMessageId":"invalid_attestation"}"#.utf8), Self.httpResponse(status: 401))
        })
        #expect(await CorpusMetadataAttachmentClient.attachResult(Self.metadataAttachment(), connection: envelope) == .attestationRejected)

        let transport = URLConnection(mockHandler: { _ in
            throw AppAttestTransportError.staleCounter
        })
        #expect(await CorpusMetadataAttachmentClient.attachResult(Self.metadataAttachment(), connection: transport) == .attestationRejected)
    }

    @Test("metadata 503 parks the queue for the default pause")
    func metadataPauseQueue() async {
        let connection = URLConnection(mockHandler: { _ in (Data(), Self.httpResponse(status: 503)) })

        let result = await CorpusMetadataAttachmentClient.attachResult(Self.metadataAttachment(), connection: connection)

        #expect(result == .pauseQueue(TranscriptUploadSender.defaultPauseDelay))
    }

    // MARK: - Gzip coder

    @Test("gzip output round-trips and carries the gzip magic")
    func gzipRoundTrip() throws {
        let original = Data("WEBVTT\n\n00:00.000 --> 00:02.000\nhello world\n".utf8)
        let compressed = try GzipCoder.gzip(original)
        #expect(compressed.prefix(2) == Data([0x1f, 0x8b]))
        #expect(try GzipCoder.gunzip(compressed) == original)
    }

    @Test("gzip of empty data round-trips")
    func gzipEmptyRoundTrip() throws {
        let compressed = try GzipCoder.gzip(Data())
        #expect(try GzipCoder.gunzip(compressed).isEmpty)
    }

    @Test("gunzip rejects non-gzip data")
    func gunzipRejectsGarbage() {
        #expect(throws: GzipCoder.GzipError.self) {
            try GzipCoder.gunzip(Data("definitely not gzip".utf8))
        }
    }

    @Test("gunzip rejects a corrupted checksum")
    func gunzipRejectsBadChecksum() throws {
        var compressed = try GzipCoder.gzip(Data("payload".utf8))
        compressed[compressed.count - 5] ^= 0xff // corrupt the CRC32 in the trailer
        #expect(throws: GzipCoder.GzipError.self) {
            try GzipCoder.gunzip(compressed)
        }
    }
}
