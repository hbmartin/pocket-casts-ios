import XCTest

@testable import podcasts

final class ReferenceFingerprintTests: XCTestCase {

    func testLibraryCheckpointsDecodeLittleEndianUInt32Hashes() throws {
        let payload = Data([
            0x78, 0x56, 0x34, 0x12,
            0xef, 0xcd, 0xab, 0x90
        ])
        let json = """
        {
            "format": "\(ReferenceFingerprint.supportedFormat)",
            "total_duration": 30,
            "checkpoint_interval": 2,
            "checkpoint_duration": 4,
            "timestamp_quantum": 2,
            "checkpoints": [
                [3, "\(payload.base64EncodedString())"]
            ]
        }
        """

        let fingerprint = try XCTUnwrap(ReferenceFingerprint.decode(from: Data(json.utf8)))
        let checkpoint = try XCTUnwrap(fingerprint.libraryCheckpoints().first)

        XCTAssertEqual(checkpoint.timestampSeconds, 6, accuracy: 0.001)
        XCTAssertEqual(checkpoint.hashes, [
            UInt32(0x12345678),
            UInt32(0x90abcdef)
        ])
    }
}
