import Foundation

public struct CorpusMetadataAttachment: Codable, Equatable, Sendable {
    public struct Chapter: Codable, Equatable, Sendable {
        public let title: String
        public let timestamp: String
        public let startTime: Double

        public init(title: String, timestamp: String, startTime: Double) {
            self.title = title
            self.timestamp = timestamp
            self.startTime = startTime
        }
    }

    public let candidateId: String
    public let attachmentToken: String
    public let summary: String
    public let chapters: [Chapter]

    public init(candidateID: String, attachmentToken: String, summary: String, chapters: [Chapter]) {
        candidateId = candidateID
        self.attachmentToken = attachmentToken
        self.summary = summary
        self.chapters = chapters
    }
}

public struct CorpusMetadataAttachmentClient: Sendable {
    private let connection: URLConnection

    public init(connection: URLConnection = URLConnection(handler: URLSession.shared)) {
        self.connection = connection
    }

    public func attach(_ metadata: CorpusMetadataAttachment) async -> Bool {
        guard let url = URL(string: ServerConstants.Urls.api() + "transcripts/contribute/metadata"),
              let body = try? JSONEncoder().encode(metadata), body.count <= 128 * 1024
        else { return false }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: ServerConstants.Timeouts.general)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: ServerConstants.HttpHeaders.contentType)
        request.setValue("application/json", forHTTPHeaderField: ServerConstants.HttpHeaders.accept)
        do {
            let (_, response) = try await connection.send(request: request)
            return (response as? HTTPURLResponse)?.statusCode == 204
        } catch {
            return false
        }
    }
}
