import Foundation
import Testing
@testable import PocketCastsTranscription

struct ElevenLabsProviderTests {
    private func makeProvider() -> (ElevenLabsProvider, apiKey: String) {
        (ElevenLabsProvider(session: MockURLProtocol.makeSession()), "elevenlabs-test-\(UUID().uuidString)")
    }

    private func makeAudioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("el-\(UUID().uuidString).m4a")
        try Data("fake audio".utf8).write(to: url)
        return url
    }

    @Test func submitGroupsWordsIntoSpeakerUtterances() async throws {
        let (provider, apiKey) = makeProvider()
        defer { MockURLProtocol.unregister(apiKey: apiKey) }
        MockURLProtocol.register(apiKey: apiKey) { request in
            guard request.url?.path == "/v1/speech-to-text" else { return .respond(statusCode: 404) }
            let body = String(decoding: MockURLProtocol.bodyData(of: request), as: UTF8.self)
            guard body.contains("scribe_v2"), body.contains("name=\"diarize\"") else {
                return .respond(statusCode: 400, body: Data("missing multipart fields".utf8))
            }
            // Word stream carries its own "spacing" tokens between words.
            return .json("""
            {
                "language_code": "en",
                "text": "Hello there. Hi back.",
                "words": [
                    {"text": "Hello", "start": 0.1, "end": 0.5, "type": "word", "speaker_id": "speaker_0"},
                    {"text": " ", "start": 0.5, "end": 0.55, "type": "spacing", "speaker_id": "speaker_0"},
                    {"text": "there.", "start": 0.55, "end": 1.0, "type": "word", "speaker_id": "speaker_0"},
                    {"text": "Hi", "start": 1.6, "end": 1.9, "type": "word", "speaker_id": "speaker_1"},
                    {"text": " ", "start": 1.9, "end": 1.95, "type": "spacing", "speaker_id": "speaker_1"},
                    {"text": "back.", "start": 1.95, "end": 2.4, "type": "word", "speaker_id": "speaker_1"}
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
            Issue.record("Expected synchronous .completed, got \(outcome)")
            return
        }
        #expect(transcript.cues == [
            DiarizedCue(speaker: "Speaker 1", text: "Hello there.", start: 0.1, end: 1.0),
            DiarizedCue(speaker: "Speaker 2", text: "Hi back.", start: 1.6, end: 2.4),
        ])
        #expect(transcript.speakerCount == 2)
        #expect(transcript.language == "en")
        #expect(transcript.engineDescription == "elevenlabs.scribe_v2")
    }

    @Test func submitSingleSpeakerEmitsUnlabeledCues() async throws {
        let (provider, apiKey) = makeProvider()
        defer { MockURLProtocol.unregister(apiKey: apiKey) }
        MockURLProtocol.register(apiKey: apiKey) { _ in
            .json("""
            {
                "language_code": "en",
                "words": [
                    {"text": "Solo", "start": 0.0, "end": 0.4, "type": "word", "speaker_id": "speaker_0"},
                    {"text": " ", "start": 0.4, "end": 0.45, "type": "spacing", "speaker_id": "speaker_0"},
                    {"text": "show.", "start": 0.45, "end": 0.9, "type": "word", "speaker_id": "speaker_0"}
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
        #expect(transcript.cues == [DiarizedCue(speaker: nil, text: "Solo show.", start: 0, end: 0.9)])
        #expect(transcript.speakerCount == 1)
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

    @Test func submitWith429ThrowsQuotaExceeded() async throws {
        let (provider, apiKey) = makeProvider()
        defer { MockURLProtocol.unregister(apiKey: apiKey) }
        MockURLProtocol.register(apiKey: apiKey) { _ in .respond(statusCode: 429) }

        let fileURL = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        await #expect(throws: TranscriptionError.quotaExceeded) {
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
