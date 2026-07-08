import XCTest
@testable import PocketCastsFileSync

final class OpLogFileTests: XCTestCase {
    private func envelope(seq: UInt64, device: String = "device-a") -> Filesync_OpEnvelope {
        var envelope = Filesync_OpEnvelope()
        envelope.opID = "op-\(seq)"
        envelope.deviceID = device
        envelope.seq = seq
        envelope.wallClockMs = 1_767_225_600_000 + Int64(seq)
        var episode = Api_SyncUserEpisode()
        episode.uuid = "ep-\(seq)"
        episode.playedUpTo = .with { $0.value = Int64(seq) * 10 }
        episode.playedUpToModified = .with { $0.value = envelope.wallClockMs }
        var record = Api_Record()
        record.episode = episode
        envelope.record = record
        return envelope
    }

    func testEncodeDecodeRoundTrip() throws {
        let envelopes = (1...50).map { envelope(seq: UInt64($0)) }
        let data = try OpLogFile.encode(envelopes)

        let result = try OpLogFile.decode(data)
        XCTAssertFalse(result.truncated)
        XCTAssertEqual(result.envelopes, envelopes)
    }

    func testEmptyDataDecodesToNothing() throws {
        let result = try OpLogFile.decode(Data())
        XCTAssertTrue(result.envelopes.isEmpty)
        XCTAssertFalse(result.truncated)
    }

    func testTruncatedTailRecoversCompleteRecords() throws {
        let envelopes = (1...5).map { envelope(seq: UInt64($0)) }
        var data = try OpLogFile.encode(envelopes)
        // Chop into the last record's body: a partially propagated file.
        data.removeLast(7)

        let result = try OpLogFile.decode(data)
        XCTAssertTrue(result.truncated)
        XCTAssertEqual(result.envelopes, Array(envelopes.prefix(4)),
                       "every record before the truncation point must survive")
    }

    func testTruncatedVarintPrefixIsTolerated() throws {
        let envelopes = [envelope(seq: 1)]
        var data = try OpLogFile.encode(envelopes)
        // A lone continuation byte where the next length prefix would start.
        data.append(0x80)

        let result = try OpLogFile.decode(data)
        XCTAssertTrue(result.truncated)
        XCTAssertEqual(result.envelopes, envelopes)
    }

    func testMalformedLengthThrows() throws {
        // Varint claiming a ~16 GB record: corruption, not truncation.
        var data = OpLogFile.varint(UInt64(OpLogFile.maxRecordBytes) * 4096)
        data.append(contentsOf: [0x00, 0x01, 0x02])

        XCTAssertThrowsError(try OpLogFile.decode(data)) { error in
            guard case OpLogFile.FramingError.malformedLength = error else {
                return XCTFail("expected malformedLength, got \(error)")
            }
        }
    }

    func testDecodeFromOffsetResumesAtCursor() throws {
        let first = (1...3).map { envelope(seq: UInt64($0)) }
        let second = (4...6).map { envelope(seq: UInt64($0)) }
        var data = try OpLogFile.encode(first)
        let cursor = data.count
        try OpLogFile.append(second, to: &data)

        let (result, nextOffset) = try OpLogFile.decode(data, fromOffset: cursor)
        XCTAssertEqual(result.envelopes, second)
        XCTAssertEqual(nextOffset, data.count)

        let (empty, unchanged) = try OpLogFile.decode(data, fromOffset: data.count)
        XCTAssertTrue(empty.envelopes.isEmpty)
        XCTAssertEqual(unchanged, data.count)
    }

    func testVarintEncoding() {
        XCTAssertEqual(OpLogFile.varint(0), Data([0x00]))
        XCTAssertEqual(OpLogFile.varint(1), Data([0x01]))
        XCTAssertEqual(OpLogFile.varint(127), Data([0x7F]))
        XCTAssertEqual(OpLogFile.varint(128), Data([0x80, 0x01]))
        XCTAssertEqual(OpLogFile.varint(300), Data([0xAC, 0x02]))

        let (value, size) = OpLogFile.readVarint([0xAC, 0x02], at: 0)!
        XCTAssertEqual(value, 300)
        XCTAssertEqual(size, 2)
        XCTAssertNil(OpLogFile.readVarint([0x80], at: 0), "dangling continuation bit is incomplete")
    }
}
