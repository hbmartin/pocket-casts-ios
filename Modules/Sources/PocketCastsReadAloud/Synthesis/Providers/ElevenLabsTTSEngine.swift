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

    /// Resolves a persisted id. `nil` means an old narration that predates model
    /// selection and therefore uses the historical default; an unknown non-nil
    /// id must stay unresolved. Silently substituting another model can change
    /// both the voice and the deterministic chunk boundaries on resume.
    public static func resolve(id: String?) -> ElevenLabsModel? {
        guard let id else { return .default }
        return allCases.first { $0.id == id }
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

        var nextPageToken: String?
        var voices: [SynthesisVoice] = []
        var seenVoiceIds = Set<String>()

        repeat {
            var components = URLComponents(
                url: baseURL.appendingPathComponent("v2/voices"),
                resolvingAgainstBaseURL: false
            )
            var queryItems = [
                URLQueryItem(name: "page_size", value: "100"),
                URLQueryItem(name: "include_total_count", value: "false"),
            ]
            if let nextPageToken {
                queryItems.append(URLQueryItem(name: "next_page_token", value: nextPageToken))
            }
            components?.queryItems = queryItems
            guard let url = components?.url else { throw ReadAloudError.engineFailure }

            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

            let (data, response) = try await send(request)
            try Self.throwIfFailed(response: response, data: data)

            let decoded: VoicesResponse
            do {
                decoded = try JSONDecoder().decode(VoicesResponse.self, from: data)
            } catch {
                throw ReadAloudError.providerResponseFailure(
                    status: (response as? HTTPURLResponse)?.statusCode,
                    providerMessage: "Voice catalog response was not valid JSON."
                )
            }

            for voice in decoded.voices where seenVoiceIds.insert(voice.voice_id).inserted {
                voices.append(SynthesisVoice(
                    id: voice.voice_id,
                    name: voice.name,
                    // Every ElevenLabs voice can speak every language supported
                    // by the selected multilingual model. A verified language
                    // describes an accent/sample, not an exclusive capability.
                    language: "mul",
                    quality: .premium,
                    previewURL: voice.preview_url.flatMap(URL.init(string:))
                ))
            }

            if decoded.has_more == true {
                guard let token = decoded.next_page_token, !token.isEmpty, token != nextPageToken else {
                    throw ReadAloudError.providerResponseFailure(
                        status: (response as? HTTPURLResponse)?.statusCode,
                        providerMessage: "Voice catalog pagination did not advance."
                    )
                }
                nextPageToken = token
            } else {
                nextPageToken = nil
            }
        } while nextPageToken != nil

        return voices
    }

    /// Probes the complete voice-list operation used by narration without
    /// spending provider credits. ElevenLabs exposes no documented zero-cost
    /// dry run for the text-to-speech POST itself, so its final permission and
    /// quota check still happens when the first requested narration starts.
    public func validate(apiKey: String) async -> Result<Void, ReadAloudError> {
        do {
            _ = try await availableVoices(apiKey: apiKey)
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

        let (temporaryURL, response) = try await download(request)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let http = response as? HTTPURLResponse
        if let http, !(200 ..< 300).contains(http.statusCode) {
            let errorData = (try? Self.readPrefix(of: temporaryURL, maximumBytes: 64 * 1024)) ?? Data()
            try Self.throwIfFailed(response: response, data: errorData)
        }
        try Self.validateDownloadedAudio(at: temporaryURL, response: response)
        try Task.checkCancellation()
        try Self.installDownloadedAudio(from: temporaryURL, to: outputURL)
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

    /// `URLSession.download(for:)` streams the response into a temporary file;
    /// a 40k-character Flash request can otherwise retain tens of megabytes in
    /// RAM, multiplied by the engine's two in-flight chunks.
    private func download(_ request: URLRequest) async throws -> (URL, URLResponse) {
        do {
            return try await session.download(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw ReadAloudError.cancelled
        } catch is CancellationError {
            throw ReadAloudError.cancelled
        } catch {
            throw ReadAloudError.networkUnavailable
        }
    }

    private static func validateDownloadedAudio(at url: URL, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ReadAloudError.providerResponseFailure(status: nil, providerMessage: "Missing HTTP response.")
        }
        guard (200 ..< 300).contains(http.statusCode) else { return }

        let mimeType = http.mimeType?.lowercased()
        guard mimeType == "audio/mpeg" || mimeType == "audio/mp3" else {
            throw ReadAloudError.providerResponseFailure(
                status: http.statusCode,
                providerMessage: "Provider returned a non-audio content type."
            )
        }

        let prefix = try readPrefix(of: url, maximumBytes: 10)
        guard prefix.count >= 3 else { throw ReadAloudError.synthesisProducedNoAudio }
        let bytes = [UInt8](prefix)
        let hasID3Header = bytes.starts(with: [0x49, 0x44, 0x33])
        let hasMPEGFrameSync = bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0
        guard hasID3Header || hasMPEGFrameSync else {
            throw ReadAloudError.providerResponseFailure(
                status: http.statusCode,
                providerMessage: "Provider response did not contain MP3 audio."
            )
        }
    }

    private static func readPrefix(of url: URL, maximumBytes: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: maximumBytes) ?? Data()
    }

    /// Copies into the destination directory first, then atomically promotes
    /// the verified file. The previously completed chunk remains intact if the
    /// download, validation, or staging copy fails.
    private static func installDownloadedAudio(from downloadedURL: URL, to outputURL: URL) throws {
        let fileManager = FileManager.default
        let stagedURL = outputURL.deletingLastPathComponent().appendingPathComponent(
            ".\(outputURL.lastPathComponent).\(UUID().uuidString).download"
        )
        defer { try? fileManager.removeItem(at: stagedURL) }

        try fileManager.copyItem(at: downloadedURL, to: stagedURL)
        if fileManager.fileExists(atPath: outputURL.path) {
            _ = try fileManager.replaceItemAt(outputURL, withItemAt: stagedURL)
        } else {
            try fileManager.moveItem(at: stagedURL, to: outputURL)
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
        let message = (detail?.message ?? "").lowercased()

        if code.contains("quota_exceeded") || kind == "payment_required" || http.statusCode == 402 {
            throw ReadAloudError.providerQuotaExceeded
        }
        if code.contains("ip_not_allowed") || code.contains("ip_address_not_allowed")
            || (http.statusCode == 403 && message.contains("ip") && message.contains("allowlist")) {
            throw ReadAloudError.providerIPRestricted
        }
        if code.contains("voice_not_found") {
            throw ReadAloudError.voiceUnavailable
        }
        if kind == "authentication_error" || code.contains("invalid_api_key") {
            throw ReadAloudError.invalidAPIKey
        }
        if code.contains("permission") || code.contains("missing_permissions") {
            throw ReadAloudError.insufficientKeyPermissions
        }

        switch http.statusCode {
        case 401:
            throw ReadAloudError.invalidAPIKey
        case 403:
            throw ReadAloudError.insufficientKeyPermissions
        case 429:
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            throw ReadAloudError.rateLimited(retryAfter: retryAfter)
        default:
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
            let voice_id: String
            let name: String
            let preview_url: String?
        }
        let voices: [Voice]
        let has_more: Bool?
        let next_page_token: String?
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
