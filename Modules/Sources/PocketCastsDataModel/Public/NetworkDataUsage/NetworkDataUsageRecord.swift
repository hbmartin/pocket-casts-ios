import Foundation
import GRDB
import GRDBMacros

@GRDBRecord(table: "NetworkDataUsage")
public struct NetworkDataUsageRecord: Equatable, Sendable {
    /// `nil` encodes as NULL on insert so SQLite assigns the AUTOINCREMENT primary key.
    public var id: Int64?

    public var timestamp: Double = 0

    @GRDBColumn("episode_uuid")
    public var episodeUuid: String?

    @GRDBColumn("podcast_uuid")
    public var podcastUuid: String?

    @GRDBColumn("bytes_downloaded")
    public var bytesDownloaded: Int64 = 0

    @GRDBColumn("bytes_streamed")
    public var bytesStreamed: Int64 = 0

    @GRDBColumn("bytes_uploaded")
    public var bytesUploaded: Int64 = 0

    @GRDBColumn("operation_type")
    public var operationType = ""

    @GRDBColumn("connection_type")
    public var connectionType: Int32 = 0

    @GRDBColumn("session_type")
    public var sessionType: String?

    public init() {}
}
