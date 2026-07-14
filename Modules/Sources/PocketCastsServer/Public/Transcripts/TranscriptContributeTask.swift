import Foundation
import SwiftProtobuf

/// Uploads one transcript contribution to `POST transcripts/contribute`
/// (docs/TranscriptContributions.md §3).
///
/// The body is the `TranscriptContributionRequest` protobuf, gzip-encoded;
/// `Authorization: Bearer` is attached only when signed in, and App Attest
/// assertion headers sign the body bytes. The upload queue drives this task
/// and acts on the returned `ContributionSendResult`.
public final class TranscriptContributeTask: Sendable {
    private let sender: TranscriptUploadSender

    public init(urlConnection: URLConnection = URLConnection(handler: URLSession.shared)) {
        sender = TranscriptUploadSender(urlConnection: urlConnection)
    }

    /// Test seam: injects the fully configured sender (stub transport, token and
    /// assertion providers).
    init(sender: TranscriptUploadSender) {
        self.sender = sender
    }

    public func send(_ contribution: TranscriptContributionPayload) async -> ContributionSendResult {
        var message = Api_TranscriptContributionRequest()
        message.episodeUuid = contribution.episodeUuid
        message.podcastUuid = contribution.podcastUuid
        message.vtt = contribution.gzippedVtt
        message.fingerprint = contribution.gzippedFingerprint
        message.engine = contribution.engine
        message.modelID = contribution.modelId
        message.language = contribution.language
        message.diarized = contribution.diarized
        message.appVersion = contribution.appVersion
        message.episodeDurationSeconds = contribution.episodeDurationSeconds
        message.createdAt = Google_Protobuf_Timestamp(date: contribution.createdAt)

        guard let messageData = try? message.serializedData() else {
            return .permanentFailure("Failed to serialize Api_TranscriptContributionRequest")
        }
        return await sender.post(messageData: messageData, to: ServerConstants.Urls.transcriptContributeUrl)
    }
}
