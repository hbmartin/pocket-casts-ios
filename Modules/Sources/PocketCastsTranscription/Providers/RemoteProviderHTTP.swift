import Foundation

/// Shared HTTP plumbing for the remote transcription providers: request execution
/// with transport-error mapping, HTTP-status → `TranscriptionError` mapping, and
/// defensive JSON decoding. Pure Foundation — no package dependencies — and no
/// logging, so an API key can never leak into a log message.
enum RemoteProviderHTTP {
    /// How much of an error response body is surfaced in `remoteResponseFailure`
    /// messages. Bodies are provider error JSON, never key material.
    private static let bodyExcerptLimit = 300

    /// Executes the request, mapping transport failures to `.networkUnavailable`
    /// (and cancellation to `CancellationError` so the queue treats it as a
    /// cancel, not a failure). Non-2xx statuses throw via `error(status:body:)`.
    @discardableResult
    static func perform(_ request: URLRequest, session: URLSession) async throws -> (data: Data, response: HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            throw TranscriptionError.networkUnavailable
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.networkUnavailable
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw error(status: http.statusCode, body: data)
        }
        return (data, http)
    }

    /// Like `perform`, but streams the body from a file (multi-megabyte audio
    /// uploads shouldn't be copied into a `Data` just to send them).
    @discardableResult
    static func upload(_ request: URLRequest, fromFile fileURL: URL, session: URLSession) async throws -> (data: Data, response: HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, fromFile: fileURL)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            throw TranscriptionError.networkUnavailable
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.networkUnavailable
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw error(status: http.statusCode, body: data)
        }
        return (data, http)
    }

    /// Maps an HTTP status to the matching `TranscriptionError`:
    /// 401/403 → `.invalidAPIKey`, 402/429 → `.quotaExceeded`, everything else
    /// (other 4xx, 5xx) → `.remoteResponseFailure` carrying a response-body
    /// excerpt that only the in-memory failure state may surface.
    static func error(status: Int, body: Data?) -> TranscriptionError {
        switch status {
        case 401, 403:
            return .invalidAPIKey
        case 402, 429:
            return .quotaExceeded
        default:
            return .remoteResponseFailure(status: status, providerMessage: bodyExcerpt(body))
        }
    }

    /// Decodes `type` from `data`, converting decode failures into a
    /// `.remoteJobFailed` that names the provider (the raw body is not included —
    /// successful-response bodies can be huge).
    static func decode<T: Decodable>(_ type: T.Type, from data: Data, provider: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw TranscriptionError.remoteJobFailed("Unexpected \(provider) response format")
        }
    }

    static func bodyExcerpt(_ body: Data?) -> String {
        guard let body, !body.isEmpty, let text = String(data: body, encoding: .utf8) else { return "no response body" }
        return bodyExcerpt(text)
    }

    /// Applies the same bounded excerpt policy to provider errors decoded from
    /// successful polling responses (for example AssemblyAI's `status=error`).
    static func bodyExcerpt(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > bodyExcerptLimit ? String(trimmed.prefix(bodyExcerptLimit)) + "…" : trimmed
    }

    /// File size in bytes, or nil when it can't be determined.
    static func fileSize(of url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64)
    }
}

/// Maps a provider's raw speaker labels ("A", "0", "speaker_1", …) to
/// "Speaker N" display labels, numbered by first appearance — the same
/// normalization `SpeakerAligner` applies to local diarizer output.
struct SpeakerLabelNormalizer {
    private var labels: [String: String] = [:]

    mutating func normalized(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if let existing = labels[raw] { return existing }
        let label = "Speaker \(labels.count + 1)"
        labels[raw] = label
        return label
    }
}

/// Shared cue assembly for providers that return word-level (or already
/// utterance-level) output.
enum RemoteCueBuilder {
    /// Caps mirroring `SpeakerAligner`'s grouping limits, so remote cues render
    /// with the same rhythm as locally generated ones.
    static let maxCueDuration: TimeInterval = 15
    static let maxCueCharacters = 200

    /// One word (or spacing/audio-event token) with timings and an
    /// already-normalized speaker label.
    struct TimedWord {
        let text: String
        let start: TimeInterval
        let end: TimeInterval
        let speaker: String?
    }

    /// Groups consecutive same-speaker words into display cues, breaking at
    /// speaker changes, ~15s of audio, or ~200 characters of text.
    ///
    /// - Parameter joinWithSpaces: true when items are bare words (OpenAI) that
    ///   need single-space joining; false when the stream carries its own
    ///   spacing tokens (ElevenLabs).
    static func cues(from words: [TimedWord], joinWithSpaces: Bool) -> [DiarizedCue] {
        var cues: [DiarizedCue] = []
        var text = ""
        var speaker: String?
        var start: TimeInterval = 0
        var end: TimeInterval = 0

        func flush() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                cues.append(DiarizedCue(speaker: speaker, text: trimmed, start: start, end: end))
            }
            text = ""
        }

        for word in words {
            let isEmptyCue = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let speakerChanged = !isEmptyCue && word.speaker != speaker
            let overLimit = !isEmptyCue && (word.end - start > maxCueDuration || text.count > maxCueCharacters)
            if speakerChanged || overLimit {
                flush()
            }
            if text.isEmpty {
                speaker = word.speaker
                start = word.start
            } else if joinWithSpaces {
                text += " "
            }
            text += word.text
            end = max(end, word.end)
        }
        flush()
        return cues
    }

    /// Wraps mapped cues into a `DiarizedTranscript`, applying the aligner's
    /// monologue rule: when at most one distinct speaker exists, cues are
    /// emitted unlabeled so the transcript renders as clean prose without a
    /// redundant "Speaker 1" header.
    static func finalizeTranscript(cues: [DiarizedCue], language: String?, engineDescription: String) -> DiarizedTranscript {
        let speakers = Set(cues.compactMap(\.speaker))
        let finalCues = speakers.count <= 1
            ? cues.map { DiarizedCue(speaker: nil, text: $0.text, start: $0.start, end: $0.end) }
            : cues
        return DiarizedTranscript(cues: finalCues,
                                  language: language,
                                  speakerCount: speakers.count,
                                  engineDescription: engineDescription)
    }
}

/// Minimal `multipart/form-data` body builder for the upload-based providers.
/// Bodies are built in memory; the audio parts are transcoded mono-AAC files
/// (tens of MB at most), which keeps the copy acceptable for v1.
struct MultipartFormBuilder {
    let boundary: String
    private var body = Data()

    init(boundary: String = "pocket-casts-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    var contentTypeHeader: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    mutating func appendField(name: String, value: String) {
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        body.append(Data("\(value)\r\n".utf8))
    }

    mutating func appendFile(fieldName: String, fileName: String, mimeType: String, data: Data) {
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
    }

    func finalizedBody() -> Data {
        body + Data("--\(boundary)--\r\n".utf8)
    }
}
