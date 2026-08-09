import Foundation

/// A provider model the user can narrate with.
///
/// Curated rather than fetched. `GET /v1/models` reports
/// `maximum_text_length_per_request`, but that limit cannot be read at render
/// time: the chunker targets a fraction of it, and a resumed narration
/// re-chunks — so a limit that changed between runs would repartition text the
/// chunk files on disk are already keyed to. The limit therefore has to be a
/// constant this build knows, and the chosen model is frozen on the narration.
public struct ElevenLabsModel: Sendable, Equatable, Identifiable, CaseIterable {
    public let id: String
    public let displayName: String
    /// Documented per-request character cap for this model.
    public let maxCharactersPerRequest: Int

    /// Best quality, and the default: the reason to configure a provider at all
    /// is that the built-in compact voices sound robotic.
    public static let multilingualV2 = ElevenLabsModel(
        id: "eleven_multilingual_v2",
        displayName: "Multilingual v2",
        maxCharactersPerRequest: 10_000
    )

    /// Cheaper and faster, with a far larger request cap — which for long
    /// documents also means noticeably fewer requests.
    public static let flashV2_5 = ElevenLabsModel(
        id: "eleven_flash_v2_5",
        displayName: "Flash v2.5",
        maxCharactersPerRequest: 40_000
    )

    public static let allCases: [ElevenLabsModel] = [.multilingualV2, .flashV2_5]

    public static let `default` = ElevenLabsModel.multilingualV2

    /// Resolves a persisted id. An unknown one — a model this build predates —
    /// falls back to the default rather than guessing a limit, because guessing
    /// high means 413s and guessing low is invisible.
    public static func resolve(id: String?) -> ElevenLabsModel {
        allCases.first { $0.id == id } ?? .default
    }
}

/// `NarrationEngineKind.remoteProvider` for ElevenLabs.
///
/// The module holds the client but never the credential: the key arrives as a
/// parameter, so this stays dependency-free and has no opinion about Keychain.
public struct ElevenLabsTTSEngine: SpeechSynthesisEngine {
    public static let providerId = "elevenlabs"

    public let id = ElevenLabsTTSEngine.providerId
    private let model: ElevenLabsModel
    private let session: URLSession
    private let baseURL = URL(string: "https://api.elevenlabs.io")!

    /// mp3 at 44.1kHz/128kbps: `AVAudioFile` reads it directly, so the assembler
    /// needs no special case, and the narration is re-encoded to AAC anyway.
    private static let outputFormat = "mp3_44100_128"

    public init(model: ElevenLabsModel = .default, session: URLSession = .shared) {
        self.model = model
        self.session = session
    }

    public var capabilities: EngineCapabilities {
        EngineCapabilities(
            maxCharactersPerChunk: model.maxCharactersPerRequest,
            // Deliberately low. ElevenLabs concurrency caps are plan-dependent
            // and small on the cheaper tiers, and because there is no automatic
            // retry a single 429 fails the whole narration and needs a manual
            // tap. Throughput is worth less here than not tripping the limit.
            maxConcurrentChunks: 2,
            requiresAPIKey: true,
            requiresConfirmation: true,
            // Packing paragraphs together: a document of short paragraphs is
            // otherwise one request each, and every request is a round trip and
            // a chance to fail.
            chunkBoundary: .headingsOnly
        )
    }

    // MARK: - Voices

    public func availableVoices(apiKey: String?) async throws -> [SynthesisVoice] {
        guard let apiKey, !apiKey.isEmpty else { throw ReadAloudError.apiKeyMissing }

        var request = URLRequest(url: baseURL.appendingPathComponent("v1/voices"))
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let (data, response) = try await send(request)
        try Self.throwIfFailed(response: response, data: data)

        let decoded = try JSONDecoder().decode(VoicesResponse.self, from: data)
        return decoded.voices.map { voice in
            SynthesisVoice(
                id: voice.voice_id,
                name: voice.name,
                // ElevenLabs voices are multilingual and report no single
                // language, so they are offered for any document rather than
                // filtered out by a language the API never claimed.
                language: voice.verified_languages?.first?.locale ?? "",
                quality: .premium,
                previewURL: voice.preview_url.flatMap(URL.init(string:))
            )
        }
    }

    /// Probes the cheapest authenticated GET, so the settings screen can tell a
    /// good key from a bad one without spending anything.
    public func validate(apiKey: String) async -> Result<Void, ReadAloudError> {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/voices"))
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        do {
            let (data, response) = try await send(request)
            try Self.throwIfFailed(response: response, data: data)
            return .success(())
        } catch let error as ReadAloudError {
            return .failure(error)
        } catch {
            return .failure(.networkUnavailable)
        }
    }

    // MARK: - Synthesis

    public func synthesize(
        chunk: NarrationChunk,
        voice: SynthesisVoice,
        settings: SynthesisSettings,
        apiKey: String?,
        to outputURL: URL
    ) async throws {
        guard let apiKey, !apiKey.isEmpty else { throw ReadAloudError.apiKeyMissing }
        try Task.checkCancellation()

        var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/text-to-speech/\(voice.id)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "output_format", value: Self.outputFormat)]
        guard let url = components?.url else { throw ReadAloudError.engineFailure }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SpeechRequest(text: chunk.text, model_id: model.id))

        let (data, response) = try await send(request)
        try Self.throwIfFailed(response: response, data: data)
        guard !data.isEmpty else { throw ReadAloudError.synthesisProducedNoAudio }

        try? FileManager.default.removeItem(at: outputURL)
        try data.write(to: outputURL, options: .atomic)
    }

    // MARK: - Transport

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw ReadAloudError.cancelled
        } catch {
            throw ReadAloudError.networkUnavailable
        }
    }

    /// Maps a failed response onto the error taxonomy.
    ///
    /// The distinction that matters most is a *scoped* key from an invalid one.
    /// An ElevenLabs key granted only speech-to-text authenticates perfectly and
    /// then refuses this endpoint, so reporting "invalid key" would send someone
    /// to regenerate a credential that was never the problem.
    static func throwIfFailed(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }

        let detail = try? JSONDecoder().decode(ErrorResponse.self, from: data).detail
        let code = (detail?.code ?? detail?.status ?? "").lowercased()
        let kind = (detail?.type ?? "").lowercased()

        switch http.statusCode {
        case 401:
            throw ReadAloudError.invalidAPIKey
        case 403:
            // 403 is the usual shape of "authenticated, not permitted".
            throw ReadAloudError.insufficientKeyPermissions
        case 429:
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            throw ReadAloudError.rateLimited(retryAfter: retryAfter)
        default:
            if code.contains("permission") || code.contains("missing_permissions") {
                throw ReadAloudError.insufficientKeyPermissions
            }
            if kind == "authentication_error" || code.contains("invalid_api_key") {
                throw ReadAloudError.invalidAPIKey
            }
            if kind == "rate_limit_error" {
                throw ReadAloudError.rateLimited(retryAfter: nil)
            }
            throw ReadAloudError.providerResponseFailure(
                status: http.statusCode,
                providerMessage: detail?.message ?? ""
            )
        }
    }

    // MARK: - Wire types

    private struct SpeechRequest: Encodable {
        let text: String
        let model_id: String
    }

    private struct VoicesResponse: Decodable {
        struct Voice: Decodable {
            struct VerifiedLanguage: Decodable { let locale: String? }
            let voice_id: String
            let name: String
            let preview_url: String?
            let verified_languages: [VerifiedLanguage]?
        }
        let voices: [Voice]
    }

    struct ErrorResponse: Decodable {
        struct Detail: Decodable {
            let type: String?
            let code: String?
            let status: String?
            let message: String?
        }
        let detail: Detail?
    }
}
