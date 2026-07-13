import Foundation

/// AssemblyAI speech-to-text (https://www.assemblyai.com/docs). Asynchronous job
/// API with native diarization: submit returns a job id that is polled until the
/// transcript (with `utterances[]`) is ready.
///
/// URL-based: AssemblyAI fetches `audio_url` itself, so non-downloaded episodes
/// work. When handed a local file instead (episode download URL unparseable),
/// the file is first pushed through AssemblyAI's own `/v2/upload` endpoint and
/// the returned private URL is submitted as `audio_url` — their documented
/// upload flow.
public struct AssemblyAIProvider: RemoteTranscriptionProvider {
    public static let providerId = "assemblyai"

    public let id = AssemblyAIProvider.providerId
    public let displayName = "AssemblyAI"
    public let supportsPublicURL = true

    private let baseURL = URL(string: "https://api.assemblyai.com")!
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - RemoteTranscriptionProvider

    public func submit(source: RemoteAudioSource, language: String?, apiKey: String) async throws -> SubmitOutcome {
        let audioURLString: String
        switch source {
        case .publicURL(let url):
            audioURLString = url.absoluteString
        case .fileUpload(let fileURL, _):
            audioURLString = try await upload(fileURL: fileURL, apiKey: apiKey)
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("v2/transcript"))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SubmitBody(audioUrl: audioURLString,
                                                               languageCode: Self.languageCode(from: language)))

        let (data, _) = try await RemoteProviderHTTP.perform(request, session: session)
        let response = try RemoteProviderHTTP.decode(TranscriptResponse.self, from: data, provider: displayName)
        guard let jobId = response.id, !jobId.isEmpty else {
            throw TranscriptionError.remoteJobFailed("AssemblyAI returned no transcript id")
        }
        return .job(RemoteJobHandle(providerId: id, jobId: jobId))
    }

    public func poll(handle: RemoteJobHandle, apiKey: String) async throws -> RemoteJobStatus {
        var request = URLRequest(url: baseURL.appendingPathComponent("v2/transcript/\(handle.jobId)"))
        request.setValue(apiKey, forHTTPHeaderField: "authorization")

        let (data, _) = try await RemoteProviderHTTP.perform(request, session: session)
        let response = try RemoteProviderHTTP.decode(TranscriptResponse.self, from: data, provider: displayName)

        switch response.status {
        case "queued", "processing":
            return .processing(nil)
        case "completed":
            return .completed(makeTranscript(from: response))
        case "error":
            return .failed(.remoteJobFailed(response.error ?? "AssemblyAI reported an unknown error"))
        default:
            // Unknown states are treated as still-working; the queue's overall
            // deadline bounds how long that optimism can last.
            return .processing(nil)
        }
    }

    // MARK: - Upload

    /// POST /v2/upload streams the raw file body; the response's `upload_url` is
    /// a private URL usable as `audio_url` in a transcript request.
    private func upload(fileURL: URL, apiKey: String) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("v2/upload"))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await RemoteProviderHTTP.upload(request, fromFile: fileURL, session: session)
        let response = try RemoteProviderHTTP.decode(UploadResponse.self, from: data, provider: displayName)
        return response.uploadUrl
    }

    // MARK: - Mapping

    private func makeTranscript(from response: TranscriptResponse) -> DiarizedTranscript {
        var normalizer = SpeakerLabelNormalizer()
        var cues: [DiarizedCue] = []

        if let utterances = response.utterances, !utterances.isEmpty {
            // Utterance timings are integer milliseconds; speakers are letters
            // ("A", "B", …) mapped to "Speaker N" by first appearance.
            cues = utterances.compactMap { utterance in
                let text = utterance.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return DiarizedCue(speaker: normalizer.normalized(utterance.speaker),
                                   text: text,
                                   start: Double(utterance.start) / 1000,
                                   end: Double(utterance.end) / 1000)
            }
        } else if let text = response.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            // Defensive: a completed transcript should carry utterances (we ask
            // for speaker_labels), but fall back to one monologue cue.
            cues = [DiarizedCue(speaker: nil, text: text, start: 0, end: response.audioDuration ?? 0)]
        }

        return RemoteCueBuilder.finalizeTranscript(cues: cues,
                                                   language: response.languageCode,
                                                   engineDescription: "assemblyai")
    }

    /// AssemblyAI expects lowercase, underscore-separated codes ("en", "en_us").
    /// Best-effort conversion from a BCP-47 tag; unknown codes are the provider's
    /// problem to reject (it errors the job with a clear message).
    static func languageCode(from language: String?) -> String? {
        guard let language, !language.isEmpty else { return nil }
        return language.lowercased().replacingOccurrences(of: "-", with: "_")
    }

    // MARK: - Wire types

    private struct SubmitBody: Encodable {
        let audioUrl: String
        var speakerLabels = true
        let languageCode: String?

        enum CodingKeys: String, CodingKey {
            case audioUrl = "audio_url"
            case speakerLabels = "speaker_labels"
            case languageCode = "language_code"
        }
    }

    private struct UploadResponse: Decodable {
        let uploadUrl: String

        enum CodingKeys: String, CodingKey {
            case uploadUrl = "upload_url"
        }
    }

    private struct TranscriptResponse: Decodable {
        let id: String?
        let status: String?
        let error: String?
        let text: String?
        let languageCode: String?
        let audioDuration: Double?
        let utterances: [Utterance]?

        enum CodingKeys: String, CodingKey {
            case id, status, error, text, utterances
            case languageCode = "language_code"
            case audioDuration = "audio_duration"
        }

        struct Utterance: Decodable {
            let speaker: String?
            let text: String
            /// Milliseconds from the start of the audio.
            let start: Int
            let end: Int
        }
    }
}
