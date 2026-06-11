import Foundation

// @unchecked Sendable: formatters are configured in their property initializers and never
// mutated afterwards; Foundation formatters are safe for concurrent reads.
public final class SizeFormatter: @unchecked Sendable {
    public static let shared = SizeFormatter()
    public var placeholder: String {
        defaultFormat(bytes: 0)
    }

    private let defaultBytesFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false

        return formatter
    }()

    private let fullRangeBytesFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false

        return formatter
    }()

    public func defaultFormat(bytes: Int64) -> String {
        defaultBytesFormatter.string(fromByteCount: bytes)
    }

    public func noDecimalFormat(bytes: Int64) -> String {
        fullRangeBytesFormatter.string(fromByteCount: bytes)
    }
}
