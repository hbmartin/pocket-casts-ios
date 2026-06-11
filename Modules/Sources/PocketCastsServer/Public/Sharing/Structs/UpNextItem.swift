import Foundation

public struct UpNextItem: Sendable {
    public var podcastUuid: String
    public var episodeUuid: String
    public var title: String?
    public var url: String
    public var published: Date
}
