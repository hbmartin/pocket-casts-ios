import Foundation
import SwiftProtobuf

/// Reports a sighting of a publisher-provided transcript to
/// `POST transcripts/sighting` (docs/TranscriptContributions.md §3).
///
/// Same wire rules as `TranscriptContributeTask`: gzipped protobuf body,
/// optional Bearer, App Attest assertion headers. The server fetches the
/// transcript content itself; a 202 only acknowledges the report.
public final class TranscriptSightingTask: Sendable {
    private let sender: TranscriptUploadSender

    public init(urlConnection: URLConnection = URLConnection(handler: URLSession.shared)) {
        sender = TranscriptUploadSender(urlConnection: urlConnection)
    }

    /// Test seam: injects the fully configured sender (stub transport, token and
    /// assertion providers).
    init(sender: TranscriptUploadSender) {
        self.sender = sender
    }

    public func send(_ sighting: TranscriptSightingPayload) async -> ContributionSendResult {
        var message = Api_TranscriptSightingRequest()
        message.episodeUuid = sighting.episodeUuid
        message.podcastUuid = sighting.podcastUuid
        message.transcriptURL = sighting.transcriptUrl
        message.format = sighting.format
        message.language = sighting.language ?? ""

        guard let messageData = try? message.serializedData() else {
            return .permanentFailure("Failed to serialize Api_TranscriptSightingRequest")
        }
        return await sender.post(messageData: messageData, to: ServerConstants.Urls.transcriptSightingUrl)
    }
}
