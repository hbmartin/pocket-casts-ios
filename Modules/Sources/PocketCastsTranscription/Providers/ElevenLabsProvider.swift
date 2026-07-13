import Foundation

/// ElevenLabs Scribe speech-to-text (https://elevenlabs.io/docs/api-reference/speech-to-text).
/// Upload-based and synchronous: one multipart request with `diarize=true`
/// returns word-level output with `speaker_id`s, which is grouped here into
/// utterance-style cues.
public struct ElevenLabsProvider: RemoteTranscriptionProvider {
    public static let providerId = "elevenlabs"

    public let id = ElevenLabsProvider.providerId
    public let displayName = "ElevenLabs"
    public let supportsPublicURL = false

    private let baseURL = URL(string: "https://api.elevenlabs.io")!
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - RemoteTranscriptionProvider

    public func submit(source: RemoteAudioSource, language: String?, apiKey: String) async throws -> SubmitOutcome {
        guard case .fileUpload(let fileURL, let mimeType) = source else {
            throw TranscriptionError.remoteJobFailed("ElevenLabs transcription requires a file upload")
        }

        var builder = MultipartFormBuilder()
        builder.appendField(name: "model_id", value: "scribe_v2")
        builder.appendField(name: "diarize", value: "true")
        if let language = Self.languageCode(from: language) {
            builder.appendField(name: "language_code", value: language)
        }
        builder.appendFile(fieldName: "file",
                           fileName: fileURL.lastPathComponent,
                           mimeType: mimeType,
                           data: try Data(contentsOf: fileURL))

        var request = URLRequest(url: baseURL.appendingPathComponent("v1/speech-to-text"))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue(builder.contentTypeHeader, forHTTPHeaderField: "Content-Type")
        request.httpBody = builder.finalizedBody()

        let (data, _) = try await RemoteProviderHTTP.perform(request, session: session)
        let response = try RemoteProviderHTTP.decode(SpeechToTextResponse.self, from: data, provider: displayName)
        return .completed(try makeTranscript(from: response, requestedLanguage: language))
    }

    public func poll(handle: RemoteJobHandle, apiKey: String) async throws -> RemoteJobStatus {
        throw TranscriptionError.remoteJobFailed("ElevenLabs transcriptions complete at submit time; there is no job to poll")
    }

    // MARK: - Mapping

    private func makeTranscript(from response: SpeechToTextResponse, requestedLanguage: String?) throws -> DiarizedTranscript {
        var normalizer = SpeakerLabelNormalizer()
        var cues: [DiarizedCue] = []

        if let words = response.words, !words.isEmpty {
            // The stream interleaves "word", "spacing" and "audio_event" tokens,
            // each carrying its own text — concatenate as-is (no extra joining).
            let timedWords: [RemoteCueBuilder.TimedWord] = words.compactMap { word in
                guard let text = word.text, !text.isEmpty else { return nil }
                return RemoteCueBuilder.TimedWord(text: text,
                                                  start: word.start ?? 0,
                                                  end: word.end ?? word.start ?? 0,
                                                  speaker: normalizer.normalized(word.speakerId))
            }
            cues = RemoteCueBuilder.cues(from: timedWords, joinWithSpaces: false)
        } else if let text = response.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            cues = [DiarizedCue(speaker: nil, text: text, start: 0, end: 0)]
        }

        guard !cues.isEmpty else {
            throw TranscriptionError.remoteJobFailed("ElevenLabs returned no transcript text")
        }

        return RemoteCueBuilder.finalizeTranscript(cues: cues,
                                                   language: response.languageCode ?? requestedLanguage,
                                                   engineDescription: "elevenlabs.scribe_v2")
    }

    /// ElevenLabs expects an ISO language code ("en"); reduce a BCP-47 tag to
    /// its primary subtag.
    static func languageCode(from language: String?) -> String? {
        guard let language, !language.isEmpty else { return nil }
        return language.split(separator: "-").first.map { String($0).lowercased() }
    }

    // MARK: - Wire types

    private struct SpeechToTextResponse: Decodable {
        let languageCode: String?
        let text: String?
        let words: [Word]?

        enum CodingKeys: String, CodingKey {
            case text, words
            case languageCode = "language_code"
        }

        struct Word: Decodable {
            let text: String?
            /// Seconds from the start of the audio (fractional).
            let start: Double?
            let end: Double?
            /// "word", "spacing" or "audio_event".
            let type: String?
            let speakerId: String?

            enum CodingKeys: String, CodingKey {
                case text, start, end, type
                case speakerId = "speaker_id"
            }
        }
    }
}
