import Foundation

/// In-memory stack of recently played episode UUIDs, used by the headphone
/// previous-episode action to step back through this session's listening order.
///
/// Most recent episode is at the top; consecutive duplicates are collapsed and
/// the stack is capped at `capacity` (oldest entries dropped first).
struct PlayedEpisodeHistory {
    let capacity: Int

    private(set) var uuids: [String] = []

    init(capacity: Int = 20) {
        self.capacity = capacity
    }

    var isEmpty: Bool {
        uuids.isEmpty
    }

    /// Pushes an episode UUID onto the history. Recording the same UUID twice
    /// in a row is a no-op so back-navigation never returns the current episode.
    mutating func record(uuid: String) {
        guard uuids.last != uuid else { return }

        uuids.append(uuid)
        if uuids.count > capacity {
            uuids.removeFirst(uuids.count - capacity)
        }
    }

    /// Pops and returns the most recently played episode UUID, or nil if the
    /// history is empty.
    mutating func popPrevious() -> String? {
        uuids.popLast()
    }

    mutating func removeAll() {
        uuids.removeAll()
    }
}
