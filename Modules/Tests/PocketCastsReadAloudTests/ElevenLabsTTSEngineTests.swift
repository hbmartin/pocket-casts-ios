import Foundation
import Testing
@testable import PocketCastsReadAloud

/// Each test uses a unique key so the mock's per-key registry keeps them
/// isolated, and suites need not be serialized.
private func makeKey(_ name: String) -> String { "key-\(name)-\(UUID().uuidString)" }

@Suite("ElevenLabs TTS engine")
struct ElevenLabsTTSEngineTests {
    private func engine(model: ElevenLabsModel = .default) -> ElevenLabsTTSEngine {
        ElevenLabsTTSEngine(model: model, session: MockURLProtocol.makeSession())
    }

    private func stub(_ key: String, _ status: Int, _ body: String, headers: [String: String] = [:]) {
        MockURLProtocol.register(apiKey: key) { _ in
            .json(body, statusCode: status, headers: headers)
        }
    }

    private func chunk(_ text: String = "Hello there.") -> NarrationChunk {
        NarrationChunk(index: 0, text: text, startsBlock: true)
    }

    private func voice() -> SynthesisVoice {
        SynthesisVoice(id: "voice-1", name: "Rachel", language: "en-US")
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("el-\(UUID().uuidString).mp3")
    }

    // MARK: - Capabilities

    /// The whole point of the packing work: a network engine pays a round trip
    /// per chunk, so it breaks only at headings.
    @Test("Reports headings-only packing and a conservative concurrency")
    func capabilities() {
        let capabilities = engine().capabilities

        #expect(capabilities.chunkBoundary == .headingsOnly)
        #expect(capabilities.requiresAPIKey)
        #expect(capabilities.requiresConfirmation)
        // Low on purpose: there is no automatic retry, so a 429 fails the whole
        // narration rather than costing a pause.
        #expect(capabilities.maxConcurrentChunks <= 3)
    }

    /// The per-request cap differs by model, which is why the model is frozen on
    /// the narration rather than read from settings.
    @Test("Chunk limit follows the model")
    func chunkLimitFollowsModel() {
        #expect(engine(model: .multilingualV2).capabilities.maxCharactersPerChunk == 10_000)
        #expect(engine(model: .flashV2_5).capabilities.maxCharactersPerChunk == 40_000)
    }

    @Test("An unknown persisted model falls back rather than guessing a limit")
    func unknownModelFallsBack() {
        #expect(ElevenLabsModel.resolve(id: "eleven_something_new_v9") == .default)
        #expect(ElevenLabsModel.resolve(id: nil) == .default)
        #expect(ElevenLabsModel.resolve(id: ElevenLabsModel.flashV2_5.id) == .flashV2_5)
    }

    // MARK: - Request shape

    @Test("Synthesis posts the text and model with the key header")
    func synthesisRequestShape() async throws {
        let key = makeKey("shape")
        defer { MockURLProtocol.unregister(apiKey: key) }
        stub(key, 200, "audio-bytes")
        let output = tempURL()
        defer { try? FileManager.default.removeItem(at: output) }

        try await engine().synthesize(
            chunk: chunk("The first move."), voice: voice(),
            settings: SynthesisSettings(), apiKey: key, to: output
        )

        let request = try #require(MockURLProtocol.requests(apiKey: key).first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path.contains("/v1/text-to-speech/voice-1") == true)
        #expect(request.url?.query?.contains("output_format=") == true)
        #expect(request.value(forHTTPHeaderField: "xi-api-key") == key)
        #expect(try Data(contentsOf: output) == Data("audio-bytes".utf8))
    }

    @Test("A missing key never reaches the network")
    func missingKeyShortCircuits() async {
        await #expect(throws: ReadAloudError.apiKeyMissing) {
            try await engine().synthesize(
                chunk: chunk(), voice: voice(), settings: SynthesisSettings(),
                apiKey: nil, to: tempURL()
            )
        }
    }

    /// An empty 200 would otherwise be written out as a zero-byte chunk file,
    /// which the resume path treats as finished work.
    @Test("An empty success body is a failure, not a silent empty chunk")
    func emptyBodyIsRejected() async {
        let key = makeKey("empty")
        defer { MockURLProtocol.unregister(apiKey: key) }
        stub(key, 200, "")

        await #expect(throws: ReadAloudError.synthesisProducedNoAudio) {
            try await engine().synthesize(
                chunk: chunk(), voice: voice(), settings: SynthesisSettings(),
                apiKey: key, to: tempURL()
            )
        }
    }

    // MARK: - Voices

    @Test("Voices decode with their free preview URL")
    func voicesDecode() async throws {
        let key = makeKey("voices")
        defer { MockURLProtocol.unregister(apiKey: key) }
        stub(key, 200, """
        {"voices":[{"voice_id":"v1","name":"Rachel","preview_url":"https://example.test/a.mp3",
        "verified_languages":[{"locale":"en-US"}]}]}
        """)

        let voices = try await engine().availableVoices(apiKey: key)

        #expect(voices.count == 1)
        #expect(voices[0].id == "v1")
        #expect(voices[0].name == "Rachel")
        #expect(voices[0].previewURL?.absoluteString == "https://example.test/a.mp3")
        #expect(voices[0].quality == .premium)
    }

    @Test("A voice with no preview simply has none")
    func voiceWithoutPreview() async throws {
        let key = makeKey("nopreview")
        defer { MockURLProtocol.unregister(apiKey: key) }
        stub(key, 200, #"{"voices":[{"voice_id":"v1","name":"Rachel"}]}"#)

        let voices = try await engine().availableVoices(apiKey: key)

        #expect(voices[0].previewURL == nil)
    }

    // MARK: - Error mapping

    /// The distinction that matters most. A key granted only speech-to-text
    /// authenticates fine and then refuses this endpoint; reporting "invalid
    /// key" would send someone to regenerate a credential that works.
    @Test("A permissions failure is not reported as an invalid key")
    func scopeFailureIsDistinct() async {
        let key = makeKey("scoped")
        defer { MockURLProtocol.unregister(apiKey: key) }
        stub(key, 403, #"{"detail":{"status":"missing_permissions","message":"text_to_speech"}}"#)

        await #expect(throws: ReadAloudError.insufficientKeyPermissions) {
            try await engine().synthesize(
                chunk: chunk(), voice: voice(), settings: SynthesisSettings(),
                apiKey: key, to: tempURL()
            )
        }
    }

    @Test("A rejected key is an invalid key")
    func unauthorized() async {
        let key = makeKey("bad")
        defer { MockURLProtocol.unregister(apiKey: key) }
        stub(key, 401, #"{"detail":{"status":"invalid_api_key"}}"#)

        await #expect(throws: ReadAloudError.invalidAPIKey) {
            try await engine().synthesize(
                chunk: chunk(), voice: voice(), settings: SynthesisSettings(),
                apiKey: key, to: tempURL()
            )
        }
    }

    @Test("Rate limiting carries the provider's retry hint")
    func rateLimited() async throws {
        let key = makeKey("429")
        defer { MockURLProtocol.unregister(apiKey: key) }
        stub(key, 429, #"{"detail":{"type":"rate_limit_error"}}"#, headers: ["Retry-After": "12"])

        do {
            try await engine().synthesize(
                chunk: chunk(), voice: voice(), settings: SynthesisSettings(),
                apiKey: key, to: tempURL()
            )
            Issue.record("expected a rate-limit error")
        } catch let error as ReadAloudError {
            #expect(error == .rateLimited(retryAfter: 12))
            #expect(error.isTransient, "a rate limit is worth telling the user to try again")
        }
    }

    /// A 4xx will simply repeat, so the message must not invite a pointless
    /// retry; a 5xx may clear on its own.
    @Test("Server errors are transient, client errors are not", arguments: [(500, true), (503, true), (422, false)])
    func transienceClassification(status: Int, expectedTransient: Bool) async throws {
        let key = makeKey("status\(status)")
        defer { MockURLProtocol.unregister(apiKey: key) }
        stub(key, status, #"{"detail":{"message":"boom"}}"#)

        do {
            try await engine().synthesize(
                chunk: chunk(), voice: voice(), settings: SynthesisSettings(),
                apiKey: key, to: tempURL()
            )
            Issue.record("expected a failure for \(status)")
        } catch let error as ReadAloudError {
            #expect(error.isTransient == expectedTransient, "wrong transience for HTTP \(status)")
        }
    }

    /// Provider text can echo the user's document, so it must not reach logs or
    /// the persisted row.
    @Test("Provider-supplied text is dropped from the sanitized description")
    func providerMessageIsNotPersisted() async throws {
        let key = makeKey("leak")
        defer { MockURLProtocol.unregister(apiKey: key) }
        stub(key, 400, #"{"detail":{"message":"the user's private sentence"}}"#)

        do {
            try await engine().synthesize(
                chunk: chunk(), voice: voice(), settings: SynthesisSettings(),
                apiKey: key, to: tempURL()
            )
            Issue.record("expected a failure")
        } catch let error as ReadAloudError {
            #expect(!error.sanitizedDescription.contains("private sentence"))
            #expect(error.code == "provider_response_failure")
        }
    }

    // MARK: - Validation

    @Test("Validation reports a working key")
    func validationSucceeds() async {
        let key = makeKey("valid")
        defer { MockURLProtocol.unregister(apiKey: key) }
        stub(key, 200, #"{"voices":[]}"#)

        #expect(await engine().validate(apiKey: key).isSuccess)
    }

    @Test("Validation separates a rejected key from a scoped one")
    func validationDistinguishesFailures() async {
        let bad = makeKey("vbad")
        defer { MockURLProtocol.unregister(apiKey: bad) }
        stub(bad, 401, #"{"detail":{"status":"invalid_api_key"}}"#)
        #expect(await engine().validate(apiKey: bad).failure == .invalidAPIKey)

        let scoped = makeKey("vscoped")
        defer { MockURLProtocol.unregister(apiKey: scoped) }
        stub(scoped, 403, #"{"detail":{"status":"missing_permissions"}}"#)
        #expect(await engine().validate(apiKey: scoped).failure == .insufficientKeyPermissions)
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
