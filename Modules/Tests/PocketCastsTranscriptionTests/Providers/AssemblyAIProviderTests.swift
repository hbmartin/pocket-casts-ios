import Foundation
import Testing
@testable import PocketCastsTranscription

struct AssemblyAIProviderTests {
    private func makeProvider() -> (AssemblyAIProvider, apiKey: String) {
        (AssemblyAIProvider(session: MockURLProtocol.makeSession()), "assemblyai-test-\(UUID().uuidString)")
    }

    // MARK: - Submit

    @Test func submitPublicURLCreatesJob() async throws {
        let (provider, apiKey) = makeProvider()
        defer { MockURLProtocol.unregister(apiKey: apiKey) }
        MockURLProtocol.register(apiKey: apiKey) { request in
            guard request.url?.path == "/v2/transcript", request.httpMethod == "POST" else {
                return .respond(statusCode: 404)
            }
            let body = try? JSONSerialization.jsonObject(with: MockURLProtocol.bodyData(of: request)) as? [String: Any]
            guard body?["audio_url"] as? String == "https://example.com/episode.mp3",
                  body?["speaker_labels"] as? Bool == true else {
                return .respond(statusCode: 400, body: Data("unexpected submit body".utf8))
            }
            return .json(#"{"id": "job-123", "status": "queued"}"#)
        }

        let outcome = try await provider.submit(source: .publicURL(URL(string: "https://example.com/episode.mp3")!),
                                                language: nil,
                                                apiKey: apiKey)

        guard case .job(let handle) = outcome else {
            Issue.record("Expected .job, got \(outcome)")
            return
        }
        #expect(handle.providerId == "assemblyai")
        #expect(handle.jobId == "job-123")
    }

    @Test func submitFileUploadPushesThroughUploadEndpoint() async throws {
        let (provider, apiKey) = makeProvider()
        defer { MockURLProtocol.unregister(apiKey: apiKey) }

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("aai-\(UUID().uuidString).m4a")
        try Data("fake audio".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        MockURLProtocol.register(apiKey: apiKey) { request in
            switch request.url?.path {
            case "/v2/upload":
                return .json(#"{"upload_url": "https://cdn.assemblyai.com/upload/private-1"}"#)
            case "/v2/transcript":
                let body = try? JSONSerialization.jsonObject(with: MockURLProtocol.bodyData(of: request)) as? [String: Any]
                guard body?["audio_url"] as? String == "https://cdn.assemblyai.com/upload/private-1" else {
                    return .respond(statusCode: 400, body: Data("upload url not forwarded".utf8))
                }
                return .json(#"{"id": "job-upload", "status": "queued"}"#)
            default:
                return .respond(statusCode: 404)
            }
        }

        let outcome = try await provider.submit(source: .fileUpload(fileURL, mimeType: "audio/mp4"),
                                                language: nil,
                                                apiKey: apiKey)

        guard case .job(let handle) = outcome else {
            Issue.record("Expected .job, got \(outcome)")
            return
        }
        #expect(handle.jobId == "job-upload")
    }

    @Test func submitWith401ThrowsInvalidAPIKey() async throws {
        let (provider, apiKey) = makeProvider()
        defer { MockURLProtocol.unregister(apiKey: apiKey) }
        MockURLProtocol.register(apiKey: apiKey) { _ in .respond(statusCode: 401) }

        await #expect(throws: TranscriptionError.invalidAPIKey) {
            _ = try await provider.submit(source: .publicURL(URL(string: "https://example.com/a.mp3")!),
                                          language: nil,
                                          apiKey: apiKey)
        }
    }

    @Test func submitWith429ThrowsQuotaExceeded() async throws {
        let (provider, apiKey) = makeProvider()
        defer { MockURLProtocol.unregister(apiKey: apiKey) }
        MockURLProtocol.register(apiKey: apiKey) { _ in .respond(statusCode: 429) }

        await #expect(throws: TranscriptionError.quotaExceeded) {
            _ = try await provider.submit(source: .publicURL(URL(string: "https://example.com/a.mp3")!),
                                          language: nil,
                                          apiKey: apiKey)
        }
    }

    @Test func submitTransportErrorThrowsNetworkUnavailable() async throws {
        let (provider, apiKey) = makeProvider()
        defer { MockURLProtocol.unregister(apiKey: apiKey) }
        MockURLProtocol.register(apiKey: apiKey) { _ in .fail(URLError(.notConnectedToInternet)) }

        await #expect(throws: TranscriptionError.networkUnavailable) {
            _ = try await provider.submit(source: .publicURL(URL(string: "https://example.com/a.mp3")!),
                                          language: nil,
                                          apiKey: apiKey)
        }
    }

    // MARK: - Poll

    private var handle: RemoteJobHandle { RemoteJobHandle(providerId: "assemblyai", jobId: "job-123") }

    @Test func pollProcessingStates() async throws {
        let (provider, apiKey) = makeProvider()
        defer { MockURLProtocol.unregister(apiKey: apiKey) }
        MockURLProtocol.register(apiKey: apiKey) { request in
            guard request.url?.path == "/v2/transcript/job-123" else { return .respond(statusCode: 404) }
            return .json(#"{"id": "job-123", "status": "processing"}"#)
        }

        let status = try await provider.poll(handle: handle, apiKey: apiKey)
        guard case .processing(let fraction) = status else {
            Issue.record("Expected .processing, got \(status)")
            return
        }
        #expect(fraction == nil)
    }

    @Test func pollCompletedMapsUtterancesToSpeakerLabeledCues() async throws {
        let (provider, apiKey) = makeProvider()
        defer { MockURLProtocol.unregister(apiKey: apiKey) }
        // Speakers appear as B first, then A: labels must follow first appearance.
        MockURLProtocol.register(apiKey: apiKey) { _ in
            .json("""
            {
                "id": "job-123",
                "status": "completed",
                "language_code": "en_us",
                "audio_duration": 12.5,
                "text": "Welcome back. Thanks for having me. Great to be here.",
                "utterances": [
                    {"speaker": "B", "text": "Welcome back.", "start": 500, "end": 2250},
                    {"speaker": "A", "text": "Thanks for having me.", "start": 2500, "end": 4000},
                    {"speaker": "B", "text": "Great to be here.", "start": 4500, "end": 6000}
                ]
            }
            """)
        }

        let status = try await provider.poll(handle: handle, apiKey: apiKey)
        guard case .completed(let transcript) = status else {
            Issue.record("Expected .completed, got \(status)")
            return
        }

        #expect(transcript.cues.count == 3)
        #expect(transcript.cues[0] == DiarizedCue(speaker: "Speaker 1", text: "Welcome back.", start: 0.5, end: 2.25))
        #expect(transcript.cues[1] == DiarizedCue(speaker: "Speaker 2", text: "Thanks for having me.", start: 2.5, end: 4))
        #expect(transcript.cues[2].speaker == "Speaker 1")
        #expect(transcript.speakerCount == 2)
        #expect(transcript.language == "en_us")
        #expect(transcript.engineDescription == "assemblyai")
    }

    @Test func pollCompletedSingleSpeakerEmitsUnlabeledCues() async throws {
        let (provider, apiKey) = makeProvider()
        defer { MockURLProtocol.unregister(apiKey: apiKey) }
        MockURLProtocol.register(apiKey: apiKey) { _ in
            .json("""
            {
                "id": "job-123",
                "status": "completed",
                "utterances": [
                    {"speaker": "A", "text": "Just me talking.", "start": 0, "end": 1500},
                    {"speaker": "A", "text": "Still just me.", "start": 2000, "end": 3500}
                ]
            }
            """)
        }

        let status = try await provider.poll(handle: handle, apiKey: apiKey)
        guard case .completed(let transcript) = status else {
            Issue.record("Expected .completed, got \(status)")
            return
        }
        #expect(transcript.cues.allSatisfy { $0.speaker == nil })
        #expect(transcript.speakerCount == 1)
    }

    @Test func pollErrorStatusMapsToRemoteJobFailed() async throws {
        let (provider, apiKey) = makeProvider()
        defer { MockURLProtocol.unregister(apiKey: apiKey) }
        MockURLProtocol.register(apiKey: apiKey) { _ in
            .json(#"{"id": "job-123", "status": "error", "error": "Audio file could not be downloaded"}"#)
        }

        let status = try await provider.poll(handle: handle, apiKey: apiKey)
        guard case .failed(let error) = status else {
            Issue.record("Expected .failed, got \(status)")
            return
        }
        #expect(error == .remoteJobFailed("Audio file could not be downloaded"))
    }

    @Test func pollWith401ThrowsInvalidAPIKey() async throws {
        let (provider, apiKey) = makeProvider()
        defer { MockURLProtocol.unregister(apiKey: apiKey) }
        MockURLProtocol.register(apiKey: apiKey) { _ in .respond(statusCode: 403) }

        await #expect(throws: TranscriptionError.invalidAPIKey) {
            _ = try await provider.poll(handle: handle, apiKey: apiKey)
        }
    }

    // MARK: - Language mapping

    @Test func languageCodesAreLowercasedAndUnderscored() {
        #expect(AssemblyAIProvider.languageCode(from: "en-US") == "en_us")
        #expect(AssemblyAIProvider.languageCode(from: "es") == "es")
        #expect(AssemblyAIProvider.languageCode(from: nil) == nil)
    }
}
