import XCTest
@testable import PocketCastsFileSync

final class UpNextMergerTests: XCTestCase {
    private func stamp(_ ms: Int64, device: String = "a", seq: UInt64 = 0) -> OpStamp {
        OpStamp(wallClockMs: ms, deviceID: device, seq: seq)
    }

    private func entry(_ uuid: String, podcast: String = "pod-1") -> Filesync_UpNextEntry {
        var entry = Filesync_UpNextEntry()
        entry.episodeUuid = uuid
        entry.podcastUuid = podcast
        return entry
    }

    private func replaceOp(_ uuids: [String]) -> Filesync_UpNextOp {
        var op = Filesync_UpNextOp()
        op.action = .replace
        op.entries = uuids.map { entry($0) }
        return op
    }

    private func singleOp(_ action: Filesync_UpNextOp.Action, _ uuid: String) -> Filesync_UpNextOp {
        var op = Filesync_UpNextOp()
        op.action = action
        op.entry = entry(uuid)
        return op
    }

    private func uuids(_ queue: [UpNextMerger.QueueEntry]) -> [String] {
        queue.map(\.episodeUuid)
    }

    func testEmptyOpsProduceEmptyQueue() {
        XCTAssertEqual(UpNextMerger.replay(ops: []), [])
    }

    func testReplaceAnchorsTheQueue() {
        let ops: [(stamp: OpStamp, op: Filesync_UpNextOp)] = [
            (stamp(1000), replaceOp(["a", "b"])),
            (stamp(2000), replaceOp(["c", "d", "e"])),
        ]
        XCTAssertEqual(uuids(UpNextMerger.replay(ops: ops)), ["c", "d", "e"],
                       "the newest replace wins wholesale")
    }

    func testAdditionsSurviveConcurrentReorder() {
        // Device A reorders (replace) at t=2000; device B added two episodes
        // at t=1500 and t=2500 while offline. The add after the reorder must
        // survive; the add before it is part of what the reorder replaced.
        let ops: [(stamp: OpStamp, op: Filesync_UpNextOp)] = [
            (stamp(1000, device: "a"), replaceOp(["x", "y"])),
            (stamp(1500, device: "b"), singleOp(.playLast, "early-add")),
            (stamp(2000, device: "a"), replaceOp(["y", "x"])),
            (stamp(2500, device: "b"), singleOp(.playLast, "late-add")),
        ]
        XCTAssertEqual(uuids(UpNextMerger.replay(ops: ops)), ["y", "x", "late-add"])
    }

    func testRemoveAfterReplaceApplies() {
        let ops: [(stamp: OpStamp, op: Filesync_UpNextOp)] = [
            (stamp(1000), replaceOp(["a", "b", "c"])),
            (stamp(2000, device: "b"), singleOp(.remove, "b")),
        ]
        XCTAssertEqual(uuids(UpNextMerger.replay(ops: ops)), ["a", "c"])
    }

    func testPlayNowInsertsAtHead() {
        let ops: [(stamp: OpStamp, op: Filesync_UpNextOp)] = [
            (stamp(1000), replaceOp(["a", "b"])),
            (stamp(2000), singleOp(.playNow, "urgent")),
        ]
        XCTAssertEqual(uuids(UpNextMerger.replay(ops: ops)), ["urgent", "a", "b"])
    }

    func testPlayNextInsertsAfterHead() {
        let ops: [(stamp: OpStamp, op: Filesync_UpNextOp)] = [
            (stamp(1000), replaceOp(["playing", "b"])),
            (stamp(2000), singleOp(.playNext, "next")),
        ]
        XCTAssertEqual(uuids(UpNextMerger.replay(ops: ops)), ["playing", "next", "b"])
    }

    func testPlayNextOnEmptyQueueAppends() {
        let ops: [(stamp: OpStamp, op: Filesync_UpNextOp)] = [
            (stamp(1000), singleOp(.playNext, "only")),
        ]
        XCTAssertEqual(uuids(UpNextMerger.replay(ops: ops)), ["only"])
    }

    func testReAddingMovesInsteadOfDuplicating() {
        let ops: [(stamp: OpStamp, op: Filesync_UpNextOp)] = [
            (stamp(1000), replaceOp(["a", "b", "c"])),
            (stamp(2000), singleOp(.playNow, "c")),
        ]
        XCTAssertEqual(uuids(UpNextMerger.replay(ops: ops)), ["c", "a", "b"])
    }

    func testNoReplayWithoutReplaceStartsEmpty() {
        let ops: [(stamp: OpStamp, op: Filesync_UpNextOp)] = [
            (stamp(1000), singleOp(.playLast, "a")),
            (stamp(2000), singleOp(.playLast, "b")),
            (stamp(3000), singleOp(.remove, "a")),
        ]
        XCTAssertEqual(uuids(UpNextMerger.replay(ops: ops)), ["b"])
    }

    func testUnsortedInputIsSortedByStamp() {
        let ops: [(stamp: OpStamp, op: Filesync_UpNextOp)] = [
            (stamp(3000), singleOp(.playLast, "late")),
            (stamp(1000), replaceOp(["base"])),
            (stamp(2000), singleOp(.playLast, "middle")),
        ]
        XCTAssertEqual(uuids(UpNextMerger.replay(ops: ops)), ["base", "middle", "late"])
    }

    func testTieBrokenByDeviceThenSeq() {
        let ops: [(stamp: OpStamp, op: Filesync_UpNextOp)] = [
            (stamp(1000, device: "b", seq: 1), singleOp(.playLast, "from-b")),
            (stamp(1000, device: "a", seq: 2), singleOp(.playLast, "from-a2")),
            (stamp(1000, device: "a", seq: 1), singleOp(.playLast, "from-a1")),
        ]
        XCTAssertEqual(uuids(UpNextMerger.replay(ops: ops)), ["from-a1", "from-a2", "from-b"])
    }
}
