import Foundation
import SwiftProtobuf

/// An episode sent person-to-person (Slice 4, docs/Social.md): sender
/// attribution, denormalized titles, an optional note and a listen-from
/// timestamp. Requires joined sender AND recipient; dies with the sender's
/// profile.
public struct SharedItem: Equatable, Sendable, Identifiable {
    public let id: Int64
    public let senderUserId: String
    public let senderHandle: String
    public let senderDisplayName: String
    public let episodeUuid: String
    public let podcastUuid: String
    public let episodeTitle: String
    public let podcastTitle: String
    public let note: String
    public let timestampSeconds: Int
    public let createdAt: Date?
    public let read: Bool

    public init(id: Int64, senderUserId: String, senderHandle: String, senderDisplayName: String,
                episodeUuid: String, podcastUuid: String, episodeTitle: String, podcastTitle: String,
                note: String, timestampSeconds: Int, createdAt: Date?, read: Bool) {
        self.id = id
        self.senderUserId = senderUserId
        self.senderHandle = senderHandle
        self.senderDisplayName = senderDisplayName
        self.episodeUuid = episodeUuid
        self.podcastUuid = podcastUuid
        self.episodeTitle = episodeTitle
        self.podcastTitle = podcastTitle
        self.note = note
        self.timestampSeconds = timestampSeconds
        self.createdAt = createdAt
        self.read = read
    }
}

/// A page of the recipient's inbox plus totals.
public struct SocialInboxPage: Equatable, Sendable {
    public let items: [SharedItem]
    public let total: Int
    public let unread: Int

    public init(items: [SharedItem], total: Int, unread: Int) {
        self.items = items
        self.total = total
        self.unread = unread
    }
}

extension SharedItem {
    init(_ api: Api_SharedItem) {
        self.init(id: api.id,
                  senderUserId: api.senderUserID,
                  senderHandle: api.senderHandle,
                  senderDisplayName: api.senderDisplayName,
                  episodeUuid: api.episodeUuid,
                  podcastUuid: api.podcastUuid,
                  episodeTitle: api.episodeTitle,
                  podcastTitle: api.podcastTitle,
                  note: api.note,
                  timestampSeconds: Int(api.timestampSeconds),
                  createdAt: api.hasCreatedAt ? api.createdAt.date : nil,
                  read: api.read)
    }
}
