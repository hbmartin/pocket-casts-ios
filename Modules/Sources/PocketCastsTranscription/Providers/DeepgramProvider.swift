import Foundation

/// Deepgram pre-recorded transcription (https://developers.deepgram.com).
/// Synchronous: a single `/v1/listen` request returns the finished, diarized
/// transcript, so `submit` maps straight to `SubmitOutcome.completed` and
/// `poll` is never reached.
///
/// URL-based: Deepgram fetches `{url}` itself, so non-downloaded episodes work.
/// When handed a local file instead, the same endpoint accepts the raw audio
/// bytes as the request body — Deepgram's documented file flow.
public struct DeepgramProvider: RemoteTranscriptionProvider {
    public static let providerId = "deepgram"

    public let id = DeepgramProvider.providerId
    public let displayName = "Deepgram"
    public let supportsPublicURL = true

    private let baseURL = URL(string: "https://api.deepgram.com")!
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - RemoteTranscriptionProvider

    public func submit(source: RemoteAudioSource, language: String?, apiKey: String) async throws -> SubmitOutcome {
        var request = URLRequest(url: listenURL(language: language))
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let data: Data
        switch source {
        case .publicURL(let url):
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["url": url.absoluteString])
            (data, _) = try await RemoteProviderHTTP.perform(request, session: session)
        case .fileUpload(let fileURL, let mimeType):
            request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
            (data, _) = try await RemoteProviderHTTP.upload(request, fromFile: fileURL, session: session)
        }

        let response = try RemoteProviderHTTP.decode(ListenResponse.self, from: data, provider: displayName)
        return .completed(try makeTranscript(from: response, requestedLanguage: language))
    }

    public func poll(handle: RemoteJobHandle, apiKey: String) async throws -> RemoteJobStatus {
        // submit() always returns .completed; a persisted Deepgram job id means the
        // record is corrupt, not that work is pending.
        throw TranscriptionError.remoteJobFailed("Deepgram transcriptions complete at submit time; there is no job to poll")
    }

    // MARK: - Request building

    private func listenURL(language: String?) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/listen"), resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "diarize", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "utterances", value: "true"),
            URLQueryItem(name: "smart_format", value: "true"),
        ]
        if let language, !language.isEmpty {
            // Deepgram accepts BCP-47 tags ("en", "en-US") directly.
            queryItems.append(URLQueryItem(name: "language", value: language))
        }
        components.queryItems = queryItems
        return components.url!
    }

    // MARK: - Mapping

    private func makeTranscript(from response: ListenResponse, requestedLanguage: String?) throws -> DiarizedTranscript {
        var normalizer = SpeakerLabelNormalizer()
        var cues: [DiarizedCue] = []

        if let utterances = response.results?.utterances, !utterances.isEmpty {
            // Speakers are integers (0, 1, …) mapped to "Speaker N" by first appearance.
            cues = utterances.compactMap { utterance in
                let text = utterance.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return DiarizedCue(speaker: normalizer.normalized(utterance.speaker.map(String.init)),
                                   text: text,
                                   start: utterance.start,
                                   end: utterance.end)
            }
        } else if let alternative = response.results?.channels?.first?.alternatives?.first,
                  case let text = alternative.transcript.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty {
            // Defensive: utterances=true should always populate utterances, but
            // fall back to the channel transcript as one monologue cue.
            cues = [DiarizedCue(speaker: nil, text: text, start: 0, end: response.metadata?.duration ?? 0)]
        }

        guard !cues.isEmpty else {
            throw TranscriptionError.remoteJobFailed("Deepgram returned no transcript text")
        }

        let language = response.results?.channels?.first?.detectedLanguage ?? requestedLanguage
        return RemoteCueBuilder.finalizeTranscript(cues: cues,
                                                   language: language,
                                                   engineDescription: "deepgram")
    }

    // MARK: - Wire types

    private struct ListenResponse: Decodable {
        let metadata: Metadata?
        let results: Results?

        struct Metadata: Decodable {
            let duration: Double?
        }

        struct Results: Decodable {
            let utterances: [Utterance]?
            let channels: [Channel]?
        }

        struct Utterance: Decodable {
            /// Seconds from the start of the audio (fractional).
            let start: Double
            let end: Double
            let transcript: String
            let speaker: Int?
        }

        struct Channel: Decodable {
            let alternatives: [Alternative]?
            let detectedLanguage: String?

            enum CodingKeys: String, CodingKey {
                case alternatives
                case detectedLanguage = "detected_language"
            }
        }

        struct Alternative: Decodable {
            let transcript: String
        }
    }
}
