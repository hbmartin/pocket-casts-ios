import Foundation

struct LogEntry {

    // MARK: - Public Properties

    let message: String
    let timestamp: Date

    var formattedForLog: String {
        "\(DateFormatHelper.sharedHelper.localTimeJsonFormat(timestamp)) \(message)"
    }

    // MARK: - Initializers

    init(_ message: String, timestamp: Date) {
        self.message = message
        self.timestamp = timestamp
    }
}
