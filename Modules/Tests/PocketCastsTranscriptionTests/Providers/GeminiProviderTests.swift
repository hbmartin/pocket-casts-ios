import Foundation
import Testing
@testable import PocketCastsTranscription

struct GeminiProviderTests {
    private func makeProvider() -> (GeminiProvider, apiKey: String) {
        (GeminiProvider(session: MockURLProtocol.makeSession()), "gemini-test-\(UUID().uuidString)")
    }

    // MARK: - Schema parsing + monotonic clamp

    @Test func parseTranscriptMapsSchemaSegments() throws {
        let payload = Data("""
        {
            "segments": [
                {"speaker": "Speaker 1", "start": 0.0, "end": 3.2, "text": "Welcome to the show."},
                {"speaker": "Speaker 2", "start": 3.5, "end": 6.0, "text": "Happy to be here."}
            ]
        }
        """.utf8)

        let transcript = try GeminiProvider.parseTranscript(payload, language: "en")

        #expect(transcript.cues == [
            DiarizedCue(speaker: "Speaker 1", text: "Welcome to the show.", start: 0, end: 3.2),
            DiarizedCue(speaker: "Speaker 2", text: "Happy to be here.", start: 3.5, end: 6.0),
        ])
        #expect(transcript.language == "en")
        #expect(transcript.speakerCount == 2)
        #expect(transcript.engineDescription == "gemini.gemini-2.5-flash")
    }

    @Test func parseTranscriptClampsRegressingAndOverlappingTimestamps() throws {
        // Model-generated timestamps drift: segment 2 starts before segment 1
        // ends, and segment 3 ends before it starts. Both must be clamped to a
        // monotonic, non-overlapping sequence.
        let payload = Data("""
        {
            "segments": [
                {"speaker": "Speaker 1", "start": 0.0, "end": 5.0, "text": "First."},
                {"speaker": "Speaker 2", "start": 3.0, "end": 7.0, "text": "Overlaps."},
                {"speaker": "Speaker 1", "start": 8.0, "end": 6.5, "text": "Ends early."}
            ]
        }
        """.utf8)

        let transcript = try GeminiProvider.parseTranscript(payload, language: nil)

        #expect(transcript.cues[0].start == 0)
        #expect(transcript.cues[0].end == 5)
        // Regressing start clamped forward to the previous cue's end.
        #expect(transcript.cues[1].start == 5)
        #expect(transcript.cues[1].end == 7)
        // End before start clamped up to its own start.
        #expect(transcript.cues[2].start == 8)
        #expect(transcript.cues[2].end == 8)
    }

    @Test func parseTranscriptNormalizesArbitrarySpeakerLabels() throws {
        // The prompt asks for "Speaker N", but the model may improvise labels;
        // they are re-normalized by first appearance.
        let payload = Data("""
        {
            "segments": [
                {"speaker": "HOST", "start": 0, "end": 1, "text": "Hi."},
                {"speaker": "GUEST", "start": 1, "end": 2, "text": "Hey."},
                {"speaker": "HOST", "start": 2, "end": 3, "text": "Welcome."}
            ]
        }
        """.utf8)

        let transcript = try GeminiProvider.parseTranscript(payload, language: nil)

        #expect(transcript.cues.map(\.speaker) == ["Speaker 1", "Speaker 2", "Speaker 1"])
    }

    @Test func parseTranscriptWithNoSegmentsThrows() {
        #expect(throws: TranscriptionError.self) {
            _ = try GeminiProvider.parseTranscript(Data(#"{"segments": []}"#.utf8), language: nil)
        }
    }

    // MARK: - Full flow

    @Test func submitRunsUploadActivationAndGenerateContent() async throws {
        let (provider, apiKey) = makeProvider()
        defer { MockURLProtocol.unregister(apiKey: apiKey) }

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("gem-\(UUID().uuidString).m4a")
        try Data("fake audio bytes".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let transcriptJSON = """
        {"segments": [
            {"speaker": "Speaker 1", "start": 0.0, "end": 2.0, "text": "Hello."},
            {"speaker": "Speaker 2", "start": 2.2, "end": 4.0, "text": "Hi."}
        ]}
        """
        // generateContent wraps the schema JSON as a string inside a candidate part.
        let generateResponse = try String(decoding: JSONSerialization.data(withJSONObject: [
            "candidates": [["content": ["parts": [["text": transcriptJSON]]]]],
        ]), as: UTF8.self)

        MockURLProtocol.register(apiKey: apiKey) { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("upload/v1beta/files") && request.value(forHTTPHeaderField: "X-Goog-Upload-Command") == "start" {
                return .respond(statusCode: 200,
                                headers: ["X-Goog-Upload-URL": "https://generativelanguage.googleapis.com/upload-session/abc"],
                                body: Data())
            }
            if path.hasSuffix("upload-session/abc") {
                return .json(#"{"file": {"name": "files/f-1", "uri": "https://generativelanguage.googleapis.com/v1beta/files/f-1", "state": "ACTIVE"}}"#)
            }
            if path.hasSuffix("models/gemini-2.5-flash:generateContent") {
                let body = try? JSONSerialization.jsonObject(with: MockURLProtocol.bodyData(of: request)) as? [String: Any]
                guard body?["generation_config"] != nil, body?["contents"] != nil else {
                    return .respond(statusCode: 400, body: Data("missing generation config".utf8))
                }
                return .json(generateResponse)
            }
            if request.httpMethod == "DELETE" {
                return .respond(statusCode: 200)
            }
            return .respond(statusCode: 404, body: Data("unexpected path \(path)".utf8))
        }

        let outcome = try await provider.submit(source: .fileUpload(fileURL, mimeType: "audio/mp4"),
                                                language: "en",
                                                apiKey: apiKey)

        guard case .completed(let transcript) = outcome else {
            Issue.record("Expected .completed, got \(outcome)")
            return
        }
        #expect(transcript.cues.count == 2)
        #expect(transcript.cues[0].speaker == "Speaker 1")
        #expect(transcript.speakerCount == 2)
    }

    @Test func submitWith403ThrowsInvalidAPIKey() async throws {
        let (provider, apiKey) = makeProvider()
        defer { MockURLProtocol.unregister(apiKey: apiKey) }
        MockURLProtocol.register(apiKey: apiKey) { _ in .respond(statusCode: 403) }

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("gem-\(UUID().uuidString).m4a")
        try Data("fake audio".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        await #expect(throws: TranscriptionError.invalidAPIKey) {
            _ = try await provider.submit(source: .fileUpload(fileURL, mimeType: "audio/mp4"),
                                          language: nil,
                                          apiKey: apiKey)
        }
    }

    @Test func submitRejectsPublicURLSources() async throws {
        let (provider, apiKey) = makeProvider()

        await #expect(throws: TranscriptionError.self) {
            _ = try await provider.submit(source: .publicURL(URL(string: "https://example.com/e.mp3")!),
                                          language: nil,
                                          apiKey: apiKey)
        }
    }
}
