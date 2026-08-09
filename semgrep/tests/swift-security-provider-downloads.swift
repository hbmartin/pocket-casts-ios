import Foundation

struct BufferedProviderEngine {
    let session: URLSession

    func synthesize(text: String, to output: URL) async throws {
        let request = URLRequest(url: URL(string: "https://provider.invalid/speech")!)
        // ruleid: pocketcasts.provider-synthesis-must-stream-file-responses, pocketcasts.server-module-raw-urlsession-transport
        let (data, _) = try await session.data(for: request)
        try data.write(to: output)
    }
}

struct StreamingProviderEngine {
    let session: URLSession

    func synthesize(text: String, to output: URL) async throws {
        let request = URLRequest(url: URL(string: "https://provider.invalid/speech")!)
        // ok: pocketcasts.provider-synthesis-must-stream-file-responses
        // ruleid: pocketcasts.server-module-raw-urlsession-transport
        let (temporaryURL, _) = try await session.download(for: request)
        try FileManager.default.moveItem(at: temporaryURL, to: output)
    }
}

struct IndirectBufferedProviderEngine {
    let session: URLSession

    func synthesize(text: String, to output: URL) async throws {
        let request = URLRequest(url: URL(string: "https://provider.invalid/speech")!)
        // ruleid: pocketcasts.provider-synthesis-must-stream-file-responses
        let (audioData, _) = try await send(request)
        try audioData.write(to: output)
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        // ruleid: pocketcasts.server-module-raw-urlsession-transport
        try await session.data(for: request)
    }
}

struct BufferedMetadataClient {
    let session: URLSession

    func fetchVoices() async throws -> Data {
        // ok: pocketcasts.provider-synthesis-must-stream-file-responses
        // ruleid: pocketcasts.server-module-raw-urlsession-transport
        try await session.data(from: URL(string: "https://provider.invalid/voices")!).0
    }
}
