import Foundation
import PocketCastsDataModel

/// Protocol mock for `DatabaseObserving`. Stub the values each stream should
/// yield by selector; the returned streams yield them in order, then finish:
/// `mock.stub("observeBadgeCount(_:)", with: [3, 5])`.
// @unchecked Sendable: restates RepositoryMock's conformance, as Swift requires of subclasses; state stays lock-guarded in the base class.
public final class DatabaseObservingMock: RepositoryMock, DatabaseObserving, @unchecked Sendable {
    public func observeHomeGrid() -> AsyncStream<HomeGridSnapshot> {
        record("observeHomeGrid()")
        return Self.stream(of: stubs["observeHomeGrid()"] as? [HomeGridSnapshot] ?? [])
    }

    public func observePlaylistEpisodeCounts() -> AsyncStream<[String: Int]> {
        record("observePlaylistEpisodeCounts()")
        return Self.stream(of: stubs["observePlaylistEpisodeCounts()"] as? [[String: Int]] ?? [])
    }

    public func observeBadgeCount(_ source: BadgeCountSource) -> AsyncStream<Int> {
        record("observeBadgeCount(_:)")
        return Self.stream(of: stubs["observeBadgeCount(_:)"] as? [Int] ?? [])
    }

    private static func stream<Value: Sendable>(of values: [Value]) -> AsyncStream<Value> {
        AsyncStream { continuation in
            for value in values {
                continuation.yield(value)
            }
            continuation.finish()
        }
    }
}
