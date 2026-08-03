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

    public func attach(_ metadata: CorpusMetadataAttachment) async -> ContributionSendResult {
        await Self.attachResult(metadata, connection: connection)
    }
}
