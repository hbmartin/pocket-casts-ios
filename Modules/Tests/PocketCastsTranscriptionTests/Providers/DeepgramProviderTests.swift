import Foundation
import Testing
@testable import PocketCastsTranscription

struct DeepgramProviderTests {
    private func makeProvider() -> (DeepgramProvider, apiKey: String) {
        (DeepgramProvider(session: MockURLProtocol.makeSession()), "deepgram-test-\(UUID().uuidString)")
    }

    @Test func submitPublicURLReturnsCompletedSynchronously() async throws {
        let (provider, apiKey) = makeProvider()
        defer { MockURLProtocol.unregister(apiKey: apiKey) }
        MockURLProtocol.register(apiKey: apiKey) { request in
            guard let url = request.url,
                  url.path == "/v1/listen",
                  let query = url.query,
                  query.contains("diarize=true"),
                  query.contains("punctuate=true"),
                  query.contains("utterances=true"),
                  query.contains("smart_format=true") else {
                return .respond(statusCode: 400, body: Data("missing query parameters".utf8))
            }
            let body = try? JSONSerialization.jsonObject(with: MockURLProtocol.bodyData(of: request)) as? [String: String]
            guard body?["url"] == "https://example.com/episode.mp3" else {
                return .respond(statusCode: 400, body: Data("missing url body".utf8))
            }
            return .json("""
            {
                "metadata": {"duration": 8.2},
                "results": {
                    "utterances": [
                        {"start": 0.08, "end": 3.5, "transcript": "Hello and welcome.", "speaker": 0},
                        {"start": 3.9, "end": 6.1, "transcript": "Glad to be here.", "speaker": 1},
                        {"start": 6.4, "end": 8.2, "transcript": "Let's begin.", "speaker": 0}
                    ]
                }
            }
            """)
        }

        let outcome = try await provider.submit(source: .publicURL(URL(string: "https://example.com/episode.mp3")!),
                                                language: nil,
                                                apiKey: apiKey)

        guard case .completed(let transcript) = outcome else {
            Issue.record("Expected synchronous .completed, got \(outcome)")
            return
        }
        #expect(transcript.cues.count == 3)
        #expect(transcript.cues[0] == DiarizedCue(speaker: "Speaker 1", text: "Hello and welcome.", start: 0.08, end: 3.5))
        #expect(transcript.cues[1].speaker == "Speaker 2")
        #expect(transcript.cues[2].speaker == "Speaker 1")
        #expect(transcript.speakerCount == 2)
        #expect(transcript.engineDescription == "deepgram")
    }

    @Test func submitFallsBackToChannelTranscriptWithoutUtterances() async throws {
        let (provider, apiKey) = makeProvider()
        defer { MockURLProtocol.unregister(apiKey: apiKey) }
        MockURLProtocol.register(apiKey: apiKey) { _ in
            .json("""
            {
                "metadata": {"duration": 4.0},
                "results": {
                    "channels": [
                        {"alternatives": [{"transcript": "A short monologue."}], "detected_language": "en"}
                    ]
                }
            }
            """)
        }

        let outcome = try await provider.submit(source: .publicURL(URL(string: "https://example.com/e.mp3")!),
                                                language: nil,
                                                apiKey: apiKey)

        guard case .completed(let transcript) = outcome else {
            Issue.record("Expected .completed, got \(outcome)")
            return
        }
        #expect(transcript.cues == [DiarizedCue(speaker: nil, text: "A short monologue.", start: 0, end: 4)])
        #expect(transcript.language == "en")
    }

    @Test func submitWith401ThrowsInvalidAPIKey() async throws {
        let (provider, apiKey) = makeProvider()
        defer { MockURLProtocol.unregister(apiKey: apiKey) }
        MockURLProtocol.register(apiKey: apiKey) { _ in .respond(statusCode: 401) }

        await #expect(throws: TranscriptionError.invalidAPIKey) {
            _ = try await provider.submit(source: .publicURL(URL(string: "https://example.com/e.mp3")!),
                                          language: nil,
                                          apiKey: apiKey)
        }
    }

    @Test func submitWith402ThrowsQuotaExceeded() async throws {
        let (provider, apiKey) = makeProvider()
        defer { MockURLProtocol.unregister(apiKey: apiKey) }
        MockURLProtocol.register(apiKey: apiKey) { _ in .respond(statusCode: 402) }

        await #expect(throws: TranscriptionError.quotaExceeded) {
            _ = try await provider.submit(source: .publicURL(URL(string: "https://example.com/e.mp3")!),
                                          language: nil,
                                          apiKey: apiKey)
        }
    }

    @Test func pollAlwaysThrows() async throws {
        let (provider, apiKey) = makeProvider()
        let handle = RemoteJobHandle(providerId: "deepgram", jobId: "bogus")

        await #expect(throws: TranscriptionError.self) {
            _ = try await provider.poll(handle: handle, apiKey: apiKey)
        }
    }
}
