import Foundation

/// OpenAI `gpt-4o-transcribe-diarize` (https://platform.openai.com/docs/guides/speech-to-text).
/// Upload-based and synchronous: one multipart request returns the diarized
/// transcript. Files are capped at 25MB, enforced locally before any bytes move
/// (episodes whose transcode still exceeds it fail `.audioTooLarge`; the settings
/// UI points users at a URL-based provider for very long episodes).
///
/// Response-shape uncertainty: the diarize model's documented response format
/// (`diarized_json`) returns speaker-labeled `segments[]`, but transcribe-family
/// endpoints have also shipped `words[]`-granularity payloads. Both shapes are
/// parsed defensively, plus a bare-`text` fallback, so a server-side format
/// change degrades to an unlabeled transcript instead of a hard failure.
public struct OpenAIProvider: RemoteTranscriptionProvider {
    public static let providerId = "openai"

    /// Documented request cap for the audio/transcriptions endpoint.
    public static let uploadLimitMB = 25

    public let id = OpenAIProvider.providerId
    public let displayName = "OpenAI"
    public let supportsPublicURL = false

    private let baseURL = URL(string: "https://api.openai.com")!
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - RemoteTranscriptionProvider

    public func submit(source: RemoteAudioSource, language: String?, apiKey: String) async throws -> SubmitOutcome {
        guard case .fileUpload(let fileURL, let mimeType) = source else {
            throw TranscriptionError.remoteJobFailed("OpenAI transcription requires a file upload")
        }
        if let size = RemoteProviderHTTP.fileSize(of: fileURL), size > Int64(Self.uploadLimitMB) * 1024 * 1024 {
            throw TranscriptionError.audioTooLarge(limitMB: Self.uploadLimitMB)
        }

        var builder = MultipartFormBuilder()
        builder.appendField(name: "model", value: "gpt-4o-transcribe-diarize")
        builder.appendField(name: "response_format", value: "diarized_json")
        // Required by the diarize model for audio longer than 30 seconds.
        builder.appendField(name: "chunking_strategy", value: "auto")
        if let language = Self.languageCode(from: language) {
            builder.appendField(name: "language", value: language)
        }
        builder.appendFile(fieldName: "file",
                           fileName: fileURL.lastPathComponent,
                           mimeType: mimeType,
                           data: try Data(contentsOf: fileURL))

        var request = URLRequest(url: baseURL.appendingPathComponent("v1/audio/transcriptions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(builder.contentTypeHeader, forHTTPHeaderField: "Content-Type")
        request.httpBody = builder.finalizedBody()

        let (data, _) = try await RemoteProviderHTTP.perform(request, session: session)
        let response = try RemoteProviderHTTP.decode(TranscriptionResponse.self, from: data, provider: displayName)
        return .completed(try makeTranscript(from: response, requestedLanguage: language))
    }

    public func poll(handle: RemoteJobHandle, apiKey: String) async throws -> RemoteJobStatus {
        throw TranscriptionError.remoteJobFailed("OpenAI transcriptions complete at submit time; there is no job to poll")
    }

    // MARK: - Mapping

    private func makeTranscript(from response: TranscriptionResponse, requestedLanguage: String?) throws -> DiarizedTranscript {
        var normalizer = SpeakerLabelNormalizer()
        var cues: [DiarizedCue] = []

        if let segments = response.segments, !segments.isEmpty {
            cues = segments.compactMap { segment in
                let text = (segment.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return DiarizedCue(speaker: normalizer.normalized(segment.speaker),
                                   text: text,
                                   start: segment.start ?? 0,
                                   end: segment.end ?? segment.start ?? 0)
            }
        } else if let words = response.words, !words.isEmpty {
            let timedWords: [RemoteCueBuilder.TimedWord] = words.compactMap { word in
                let text = (word.word ?? word.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return RemoteCueBuilder.TimedWord(text: text,
                                                  start: word.start ?? 0,
                                                  end: word.end ?? word.start ?? 0,
                                                  speaker: normalizer.normalized(word.speaker))
            }
            cues = RemoteCueBuilder.cues(from: timedWords, joinWithSpaces: true)
        } else if let text = response.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            cues = [DiarizedCue(speaker: nil, text: text, start: 0, end: response.duration ?? 0)]
        }

        guard !cues.isEmpty else {
            throw TranscriptionError.remoteJobFailed("OpenAI returned no transcript text")
        }

        return RemoteCueBuilder.finalizeTranscript(cues: cues,
                                                   language: response.language ?? requestedLanguage,
                                                   engineDescription: "openai.gpt-4o-transcribe-diarize")
    }

    /// OpenAI expects an ISO-639-1 code ("en"), so a BCP-47 tag is reduced to
    /// its primary subtag.
    static func languageCode(from language: String?) -> String? {
        guard let language, !language.isEmpty else { return nil }
        return language.split(separator: "-").first.map { String($0).lowercased() }
    }

    // MARK: - Wire types

    private struct TranscriptionResponse: Decodable {
        let text: String?
        let language: String?
        let duration: Double?
        let segments: [Segment]?
        let words: [Word]?

        struct Segment: Decodable {
            let speaker: String?
            let text: String?
            /// Seconds from the start of the audio (fractional).
            let start: Double?
            let end: Double?
        }

        struct Word: Decodable {
            /// Verbose-JSON shape uses `word`; some payloads use `text`.
            let word: String?
            let text: String?
            let speaker: String?
            let start: Double?
            let end: Double?
        }
    }
}
