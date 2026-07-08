import Foundation

enum FileSyncClock {
    static func currentUTCTimeInMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
