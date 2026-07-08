import Foundation

/// Pure op-based Up Next queue merge.
///
/// Whole-queue last-writer-wins would drop one side of any concurrent edit
/// (device A reorders while offline device B adds two episodes). Instead,
/// queue changes travel as individual ops (mirroring the app's
/// `UpNextChanges.Actions`) and every device deterministically replays the
/// same op sequence:
///
/// 1. The newest `replace` op (by stamp) is the base queue — a `replace` is
///    a deliberate whole-queue statement (reorder, clear, initial seed).
/// 2. Every later add/remove op is replayed on top in stamp order, so
///    additions and removals made concurrently with the reorder survive it.
///
/// The result can occasionally be "creative" after simultaneous reorders on
/// two devices (one reorder wins, the other's adds/removes still apply),
/// but nothing is ever silently lost.
public enum UpNextMerger {
    public struct QueueEntry: Equatable, Hashable, Sendable {
        public let episodeUuid: String
        public let podcastUuid: String

        public init(episodeUuid: String, podcastUuid: String) {
            self.episodeUuid = episodeUuid
            self.podcastUuid = podcastUuid
        }

        init(_ proto: Filesync_UpNextEntry) {
            self.init(episodeUuid: proto.episodeUuid, podcastUuid: proto.podcastUuid)
        }
    }

    /// Replays the merged op stream into a final ordered queue.
    /// `ops` may be unsorted; they are ordered by stamp internally.
    public static func replay(ops: [(stamp: OpStamp, op: Filesync_UpNextOp)]) -> [QueueEntry] {
        let sorted = ops.sorted { $0.stamp < $1.stamp }

        // Base = newest replace; ops before it are superseded by it.
        var queue: [QueueEntry] = []
        var startIndex = 0
        if let lastReplace = sorted.lastIndex(where: { $0.op.action == .replace }) {
            queue = sorted[lastReplace].op.entries.map(QueueEntry.init)
            startIndex = sorted.index(after: lastReplace)
        }

        for (_, op) in sorted[startIndex...] {
            apply(op, to: &queue)
        }
        return queue
    }

    static func apply(_ op: Filesync_UpNextOp, to queue: inout [QueueEntry]) {
        switch op.action {
        case .replace:
            queue = op.entries.map(QueueEntry.init)
        case .playNow, .playNext, .playLast:
            guard op.hasEntry, !op.entry.episodeUuid.isEmpty else { return }
            let entry = QueueEntry(op.entry)
            // An episode added again moves to its new position.
            queue.removeAll { $0.episodeUuid == entry.episodeUuid }
            switch op.action {
            case .playNow:
                queue.insert(entry, at: 0)
            case .playNext:
                queue.insert(entry, at: min(1, queue.count))
            default:
                queue.append(entry)
            }
        case .remove:
            guard op.hasEntry, !op.entry.episodeUuid.isEmpty else { return }
            queue.removeAll { $0.episodeUuid == op.entry.episodeUuid }
        case .unknown, .UNRECOGNIZED:
            break
        }
    }
}
