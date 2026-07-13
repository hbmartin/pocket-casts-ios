import Foundation

/// Google Gemini transcription via the Files API + `generateContent`
/// (https://ai.google.dev/api). Upload-based, three steps inside `submit`:
///
/// 1. Resumable upload to the Files API (`start` handshake → byte upload).
/// 2. Poll the file until its state is `ACTIVE` (server-side processing).
/// 3. `generateContent` on `gemini-2.5-flash` with a JSON `responseSchema`
///    (`{segments:[{speaker,start,end,text}]}`) and the audio file part.
///
/// Gemini's timestamps are model-generated, not measured, and drift on long
/// audio — treat them as approximate. Monotonic, non-overlapping ordering is
/// enforced post-parse (regressions are clamped) so seeking never jumps backwards.
public struct GeminiProvider: RemoteTranscriptionProvider {
    public static let providerId = "gemini"

    public let id = GeminiProvider.providerId
    public let displayName = "Google Gemini"
    public let supportsPublicURL = false

    static let model = "gemini-2.5-flash"

    private let baseURL = URL(string: "https://generativelanguage.googleapis.com")!
    private let session: URLSession

    /// How long to wait for the uploaded file to become ACTIVE (2s fixed
    /// interval; server-side audio processing is usually seconds).
    private static let fileActivationPollInterval: TimeInterval = 2
    private static let fileActivationMaxAttempts = 150 // ~5 minutes

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - RemoteTranscriptionProvider

    public func submit(source: RemoteAudioSource, language: String?, apiKey: String) async throws -> SubmitOutcome {
        guard case .fileUpload(let fileURL, let mimeType) = source else {
            throw TranscriptionError.remoteJobFailed("Gemini transcription requires a file upload")
        }

        let file = try await uploadFile(fileURL: fileURL, mimeType: mimeType, apiKey: apiKey)
        let activeFile = try await waitUntilActive(file: file, apiKey: apiKey)
        defer {
            // Best-effort cleanup; orphaned files expire server-side after 48h anyway.
            deleteFile(named: activeFile.name, apiKey: apiKey)
        }
        let transcript = try await generateTranscript(fileURI: activeFile.uri ?? "",
                                                      mimeType: mimeType,
                                                      language: language,
                                                      apiKey: apiKey)
        return .completed(transcript)
    }

    public func poll(handle: RemoteJobHandle, apiKey: String) async throws -> RemoteJobStatus {
        throw TranscriptionError.remoteJobFailed("Gemini transcriptions complete at submit time; there is no job to poll")
    }

    // MARK: - Files API

    private func uploadFile(fileURL: URL, mimeType: String, apiKey: String) async throws -> FileMetadata {
        guard let size = RemoteProviderHTTP.fileSize(of: fileURL) else {
            throw TranscriptionError.audioUnreadable
        }

        // Step 1: resumable-upload handshake; the byte-upload URL comes back in
        // the X-Goog-Upload-URL response header.
        var startRequest = URLRequest(url: baseURL.appendingPathComponent("upload/v1beta/files"))
        startRequest.httpMethod = "POST"
        startRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        startRequest.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        startRequest.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        startRequest.setValue("\(size)", forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        startRequest.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        startRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        startRequest.httpBody = try JSONEncoder().encode(StartUploadBody(file: .init(displayName: "pocket-casts-episode")))

        let (_, startResponse) = try await RemoteProviderHTTP.perform(startRequest, session: session)
        guard let uploadURLString = startResponse.value(forHTTPHeaderField: "X-Goog-Upload-URL"),
              let uploadURL = URL(string: uploadURLString) else {
            throw TranscriptionError.remoteJobFailed("Gemini did not return an upload URL")
        }

        // Step 2: single-shot byte upload (upload + finalize in one command).
        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        uploadRequest.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        uploadRequest.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")

        let (data, _) = try await RemoteProviderHTTP.upload(uploadRequest, fromFile: fileURL, session: session)
        let response = try RemoteProviderHTTP.decode(UploadFileResponse.self, from: data, provider: displayName)
        guard let file = response.file else {
            throw TranscriptionError.remoteJobFailed("Gemini upload returned no file metadata")
        }
        return file
    }

    private func waitUntilActive(file: FileMetadata, apiKey: String) async throws -> FileMetadata {
        var current = file
        var attempts = 0
        while true {
            switch current.state {
            case "ACTIVE", nil:
                // nil defensively: older payloads omitted state once processed.
                return current
            case "FAILED":
                throw TranscriptionError.remoteJobFailed("Gemini could not process the uploaded audio")
            default: // "PROCESSING" and any unknown state: keep waiting.
                attempts += 1
                guard attempts <= Self.fileActivationMaxAttempts else {
                    throw TranscriptionError.remoteJobFailed("Gemini file processing timed out")
                }
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: UInt64(Self.fileActivationPollInterval * 1_000_000_000))

                var request = URLRequest(url: baseURL.appendingPathComponent("v1beta/\(current.name)"))
                request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
                let (data, _) = try await RemoteProviderHTTP.perform(request, session: session)
                current = try RemoteProviderHTTP.decode(FileMetadata.self, from: data, provider: displayName)
            }
        }
    }

    /// Fire-and-forget DELETE of the uploaded file. Failures are ignored — the
    /// Files API expires uploads automatically.
    private func deleteFile(named name: String, apiKey: String) {
        guard !name.isEmpty else { return }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1beta/\(name)"))
        request.httpMethod = "DELETE"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let session = session
        Task { _ = try? await session.data(for: request) }
    }

    // MARK: - generateContent

    private func generateTranscript(fileURI: String, mimeType: String, language: String?, apiKey: String) async throws -> DiarizedTranscript {
        guard !fileURI.isEmpty else {
            throw TranscriptionError.remoteJobFailed("Gemini upload returned no file URI")
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("v1beta/models/\(Self.model):generateContent"))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.generateContentBody(fileURI: fileURI,
                                                                                               mimeType: mimeType,
                                                                                               language: language))

        let (data, _) = try await RemoteProviderHTTP.perform(request, session: session)
        let response = try RemoteProviderHTTP.decode(GenerateContentResponse.self, from: data, provider: displayName)
        let jsonText = (response.candidates?.first?.content?.parts ?? [])
            .compactMap(\.text)
            .joined()
        guard let payload = jsonText.data(using: .utf8), !jsonText.isEmpty else {
            throw TranscriptionError.remoteJobFailed("Gemini returned no transcript content")
        }
        return try Self.parseTranscript(payload, language: language)
    }

    /// Request body as a JSON object (snake_case field names per the REST API's
    /// proto3 JSON mapping). Built with `JSONSerialization` because the nested
    /// response schema is much clearer as literals than as `Encodable` types.
    static func generateContentBody(fileURI: String, mimeType: String, language: String?) -> [String: Any] {
        var prompt = """
        Transcribe this podcast audio with speaker diarization. Label speakers \
        "Speaker 1", "Speaker 2", … in order of first appearance. `start` and \
        `end` are seconds from the beginning of the audio, with decimals. \
        Return every spoken segment, in order, splitting segments at speaker \
        changes and natural sentence boundaries.
        """
        if let language, !language.isEmpty {
            prompt += " The audio language is \(language)."
        }

        let segmentSchema: [String: Any] = [
            "type": "OBJECT",
            "properties": [
                "speaker": ["type": "STRING"],
                "start": ["type": "NUMBER"],
                "end": ["type": "NUMBER"],
                "text": ["type": "STRING"],
            ],
            "required": ["speaker", "start", "end", "text"],
        ]
        let responseSchema: [String: Any] = [
            "type": "OBJECT",
            "properties": ["segments": ["type": "ARRAY", "items": segmentSchema]],
            "required": ["segments"],
        ]

        return [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    ["file_data": ["mime_type": mimeType, "file_uri": fileURI]],
                ],
            ]],
            "generation_config": [
                "response_mime_type": "application/json",
                "response_schema": responseSchema,
            ],
        ]
    }

    // MARK: - Parsing

    /// Decodes the schema-constrained JSON and enforces monotonic,
    /// non-overlapping timestamps: a start earlier than the previous cue's end
    /// is clamped forward, and an end earlier than its own start is clamped up.
    /// Internal (not private) so the clamping rules are directly unit-testable.
    static func parseTranscript(_ data: Data, language: String?) throws -> DiarizedTranscript {
        let payload = try RemoteProviderHTTP.decode(TranscriptPayload.self, from: data, provider: "Gemini")
        var normalizer = SpeakerLabelNormalizer()
        var cues: [DiarizedCue] = []
        var previousEnd: TimeInterval = 0

        for segment in payload.segments ?? [] {
            let text = (segment.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            var start = max(segment.start ?? previousEnd, 0)
            var end = max(segment.end ?? start, 0)
            if start < previousEnd { start = previousEnd }
            if end < start { end = start }
            previousEnd = end

            cues.append(DiarizedCue(speaker: normalizer.normalized(segment.speaker),
                                    text: text,
                                    start: start,
                                    end: end))
        }

        guard !cues.isEmpty else {
            throw TranscriptionError.remoteJobFailed("Gemini returned no transcript segments")
        }

        return RemoteCueBuilder.finalizeTranscript(cues: cues,
                                                   language: language,
                                                   engineDescription: "gemini.\(model)")
    }

    // MARK: - Wire types

    private struct StartUploadBody: Encodable {
        struct File: Encodable {
            let displayName: String

            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
            }
        }

        let file: File
    }

    private struct UploadFileResponse: Decodable {
        let file: FileMetadata?
    }

    struct FileMetadata: Decodable {
        /// Resource name, e.g. "files/abc-123".
        let name: String
        let uri: String?
        /// "PROCESSING", "ACTIVE" or "FAILED".
        let state: String?
    }

    private struct GenerateContentResponse: Decodable {
        let candidates: [Candidate]?

        struct Candidate: Decodable {
            let content: Content?
        }

        struct Content: Decodable {
            let parts: [Part]?
        }

        struct Part: Decodable {
            let text: String?
        }
    }

    struct TranscriptPayload: Decodable {
        let segments: [Segment]?

        struct Segment: Decodable {
            let speaker: String?
            let start: Double?
            let end: Double?
            let text: String?
        }
    }
}
