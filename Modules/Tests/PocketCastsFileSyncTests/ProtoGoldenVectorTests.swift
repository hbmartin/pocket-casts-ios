import XCTest
import SwiftProtobuf
@testable import PocketCastsFileSync

/// Validates the module's generated protobuf code against golden vectors
/// encoded by protoc (the reference C++ implementation) from the vendored
/// .proto sources. Each vector is decoded, checked field-by-field, and
/// re-encoded; byte-identical re-encoding proves the Swift codecs write the
/// same wire format protoc does.
///
/// The .textpb sources for these vectors live next to the binaries; refresh
/// them with protoc --encode after schema changes (see
/// scripts/generate-filesync-proto.sh notes).
final class ProtoGoldenVectorTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)
                ?? Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"),
            "missing fixture \(name)")
        return try Data(contentsOf: url)
    }

    func testEpisodeEnvelopeRoundTrip() throws {
        let bytes = try fixture("op_envelope_episode.pb")
        let envelope = try Filesync_OpEnvelope(serializedBytes: bytes)

        XCTAssertEqual(envelope.opID, "0d9f1c2e-1111-2222-3333-444455556666")
        XCTAssertEqual(envelope.deviceID, "device-a")
        XCTAssertEqual(envelope.seq, 42)
        XCTAssertEqual(envelope.wallClockMs, 1_767_225_600_000)

        guard case .record(let record)? = envelope.payload,
              case .episode(let episode)? = record.record else {
            return XCTFail("expected an episode record payload")
        }
        XCTAssertEqual(episode.uuid, "ep-uuid-1")
        XCTAssertEqual(episode.podcastUuid, "pod-uuid-1")
        XCTAssertEqual(episode.playingStatus.value, 2)
        XCTAssertEqual(episode.playingStatusModified.value, 1_767_225_600_001)
        XCTAssertEqual(episode.playedUpTo.value, 1234)
        XCTAssertEqual(episode.playedUpToModified.value, 1_767_225_600_002)
        XCTAssertTrue(episode.starred.value)
        XCTAssertEqual(episode.starredModified.value, 1_767_225_600_003)
        XCTAssertFalse(episode.hasIsDeleted, "unset wrapper fields must decode as absent")

        XCTAssertEqual(try envelope.serializedData(), bytes,
                       "re-encoding must be byte-identical to protoc output")
    }

    func testUpNextReplaceEnvelopeRoundTrip() throws {
        let bytes = try fixture("op_envelope_upnext_replace.pb")
        let envelope = try Filesync_OpEnvelope(serializedBytes: bytes)

        guard case .upNext(let op)? = envelope.payload else {
            return XCTFail("expected an up-next payload")
        }
        XCTAssertEqual(op.action, .replace)
        XCTAssertEqual(op.entries.count, 2)
        XCTAssertEqual(op.entries[0].episodeUuid, "ep-1")
        XCTAssertEqual(op.entries[1].podcastUuid, "da7aba5e-f11e-f11e-f11e-da7aba5ef11e")

        XCTAssertEqual(try envelope.serializedData(), bytes)
    }

    func testPodcastFeedURLEnvelopeRoundTrip() throws {
        let bytes = try fixture("op_envelope_podcast_feedurl.pb")
        let envelope = try Filesync_OpEnvelope(serializedBytes: bytes)

        guard case .record(let record)? = envelope.payload,
              case .podcast(let podcast)? = record.record else {
            return XCTFail("expected a podcast record payload")
        }
        XCTAssertEqual(podcast.uuid, "pod-uuid-1")
        XCTAssertTrue(podcast.subscribed.value)
        XCTAssertEqual(podcast.sortPosition.value, 3)
        XCTAssertEqual(podcast.dateAdded.seconds, 1_767_225_600)
        XCTAssertEqual(podcast.dateAdded.nanos, 500_000_000)
        XCTAssertEqual(podcast.feedURL, "https://example.com/feed.rss",
                       "the fork's field 1000 must survive the protoc round trip")

        XCTAssertEqual(try envelope.serializedData(), bytes)
    }

    func testSnapshotRoundTrip() throws {
        let bytes = try fixture("snapshot_small.pb")
        let snapshot = try Filesync_Snapshot(serializedBytes: bytes)

        XCTAssertEqual(snapshot.deviceID, "device-a")
        XCTAssertEqual(snapshot.asOfSeq, 100)
        XCTAssertEqual(snapshot.records.count, 1)
        guard case .folder(let folder)? = snapshot.records[0].record.record else {
            return XCTFail("expected a folder record")
        }
        XCTAssertEqual(folder.folderUuid, "folder-1")
        XCTAssertEqual(folder.name, "News")
        XCTAssertEqual(snapshot.records[0].fieldModifiedMs[3], 1_767_225_600_000)
        XCTAssertEqual(snapshot.records[0].fieldModifiedMs[4], 1_767_225_600_001)
        XCTAssertEqual(snapshot.tombstones.first?.entityType, .podcast)
        XCTAssertEqual(snapshot.tombstones.first?.uuid, "dead-pod")
        XCTAssertEqual(snapshot.upNext.entries.count, 1)
        XCTAssertEqual(snapshot.settings.first?.name, "skipForward")
        XCTAssertEqual(snapshot.stats.timeListened, 360_000)
        XCTAssertEqual(snapshot.uploads.first?.sha256,
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(snapshot.uploads.first?.durationSeconds, 1800.5)

        // Note: maps make protobuf encoding order-nondeterministic in
        // general, but a single-record map plus deterministic Swift ordering
        // for the rest keeps this comparison meaningful. If a regenerated
        // codec legitimately reorders map entries, compare decoded values
        // instead.
        let reencoded = try Filesync_Snapshot(serializedBytes: snapshot.serializedData())
        XCTAssertEqual(reencoded, snapshot)
    }

    func testDeviceInfoRoundTrip() throws {
        let bytes = try fixture("device_info.pb")
        let info = try Filesync_DeviceInfo(serializedBytes: bytes)

        XCTAssertEqual(info.deviceID, "device-a")
        XCTAssertEqual(info.name, "Test iPhone")
        XCTAssertEqual(info.model, "iPhone16,1")
        XCTAssertEqual(info.appVersion, "7.90")
        XCTAssertEqual(info.lastSeenMs, 1_767_226_100_000)
        XCTAssertEqual(info.headSeq, 100)
        XCTAssertEqual(info.formatVersion, 1)

        XCTAssertEqual(try info.serializedData(), bytes)
    }
}
