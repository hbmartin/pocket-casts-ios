import Foundation
import Testing
@testable import PocketCastsTranscription

struct OpenAIProviderTests {
    private func makeProvider() -> (OpenAIProvider, apiKey: String) {
        (OpenAIProvider(session: MockURLProtocol.makeSession()), "openai-test-\(UUID().uuidString)")
    }

    private func makeAudioFile(bytes: Int = 16) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("oai-\(UUID().uuidString).m4a")
        try Data(count: bytes).write(to: url)
        return url
    }

    @Test func oversizeFileFailsBeforeAnyRequest() async throws {
        let (provider, apiKey) = makeProvider()
        defer { MockURLProtocol.unregister(apiKey: apiKey) }
        MockURLProtocol.register(apiKey: apiKey) { _ in
            .respond(statusCode: 500, body: Data("the pre-check must prevent this request".utf8))
        }

        let fileURL = try makeAudioFile(bytes: 26 * 1024 * 1024)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        await #expect(throws: TranscriptionError.audioTooLarge(limitMB: 25)) {
            _ = try await provider.submit(source: .fileUpload(fileURL, mimeType: "audio/mp4"),
                                          language: nil,
                                          apiKey: apiKey)
        }
    }

    @Test func submitMapsDiarizedSegments() async throws {
        let (provider, apiKey) = makeProvider()
        defer { MockURLProtocol.unregister(apiKey: apiKey) }
        MockURLProtocol.register(apiKey: apiKey) { request in
            guard request.url?.path == "/v1/audio/transcriptions" else { return .respond(statusCode: 404) }
            let body = String(decoding: MockURLProtocol.bodyData(of: request), as: UTF8.self)
            guard body.contains("gpt-4o-transcribe-diarize"), body.contains("diarized_json") else {
                return .respond(statusCode: 400, body: Data("missing multipart fields".utf8))
            }
            return .json("""
            {
                "task": "transcribe",
                "language": "en",
                "duration": 7.5,
                "text": "Hi there. Hello back.",
                "segments": [
                    {"speaker": "A", "text": "Hi there.", "start": 0.0, "end": 2.4},
                    {"speaker": "B", "text": "Hello back.", "start": 2.9, "end": 4.8}
                ]
            }
            """)
        }

        let fileURL = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let outcome = try await provider.submit(source: .fileUpload(fileURL, mimeType: "audio/mp4"),
                                                language: "en-US",
                                                apiKey: apiKey)

        guard case .completed(let transcript) = outcome else {
            Issue.record("Expected .completed, got \(outcome)")
            return
        }
        #expect(transcript.cues == [
            DiarizedCue(speaker: "Speaker 1", text: "Hi there.", start: 0, end: 2.4),
            DiarizedCue(speaker: "Speaker 2", text: "Hello back.", start: 2.9, end: 4.8),
        ])
        #expect(transcript.language == "en")
        #expect(transcript.speakerCount == 2)
    }

    @Test func submitMapsWordLevelResponsesByGrouping() async throws {
        let (provider, apiKey) = makeProvider()
        defer { MockURLProtocol.unregister(apiKey: apiKey) }
        MockURLProtocol.register(apiKey: apiKey) { _ in
            .json("""
            {
                "text": "Hi there everyone hello",
                "words": [
                    {"word": "Hi", "start": 0.0, "end": 0.4, "speaker": "A"},
                    {"word": "there", "start": 0.5, "end": 0.9, "speaker": "A"},
                    {"word": "everyone", "start": 1.0, "end": 1.6, "speaker": "A"},
                    {"word": "hello", "start": 2.0, "end": 2.5, "speaker": "B"}
                ]
            }
            """)
        }

        let fileURL = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let outcome = try await provider.submit(source: .fileUpload(fileURL, mimeType: "audio/mp4"),
                                                language: nil,
                                                apiKey: apiKey)

        guard case .completed(let transcript) = outcome else {
            Issue.record("Expected .completed, got \(outcome)")
            return
        }
        #expect(transcript.cues == [
            DiarizedCue(speaker: "Speaker 1", text: "Hi there everyone", start: 0, end: 1.6),
            DiarizedCue(speaker: "Speaker 2", text: "hello", start: 2.0, end: 2.5),
        ])
    }

    @Test func submitFallsBackToPlainText() async throws {
        let (provider, apiKey) = makeProvider()
        defer { MockURLProtocol.unregister(apiKey: apiKey) }
        MockURLProtocol.register(apiKey: apiKey) { _ in
            .json(#"{"text": "Just a plain transcript.", "duration": 3.0}"#)
        }

        let fileURL = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let outcome = try await provider.submit(source: .fileUpload(fileURL, mimeType: "audio/mp4"),
                                                language: nil,
                                                apiKey: apiKey)

        guard case .completed(let transcript) = outcome else {
            Issue.record("Expected .completed, got \(outcome)")
            return
        }
        #expect(transcript.cues == [DiarizedCue(speaker: nil, text: "Just a plain transcript.", start: 0, end: 3)])
    }

    @Test func submitWith401ThrowsInvalidAPIKey() async throws {
        let (provider, apiKey) = makeProvider()
        defer { MockURLProtocol.unregister(apiKey: apiKey) }
        MockURLProtocol.register(apiKey: apiKey) { _ in .respond(statusCode: 401) }

        let fileURL = try makeAudioFile()
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

    @Test func languageCodesReduceToPrimarySubtag() {
        #expect(OpenAIProvider.languageCode(from: "en-US") == "en")
        #expect(OpenAIProvider.languageCode(from: "pt") == "pt")
        #expect(OpenAIProvider.languageCode(from: nil) == nil)
    }
}
