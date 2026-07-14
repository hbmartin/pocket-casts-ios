import AVFoundation
import Fingerprint
import XCTest

@testable import podcasts

final class ReferenceFingerprintEncoderTests: XCTestCase {

    // MARK: - Round trip: encoder output → ReferenceFingerprint decoder

    func testEncodeRoundTripsThroughReferenceFingerprintDecoder() throws {
        let windows = [
            WindowedFingerprint(timestampMs: 0, durationMs: 8000, hashes: [0x12345678, 0x90ABCDEF]),
            WindowedFingerprint(timestampMs: 2000, durationMs: 8000, hashes: [1, 2, 3]),
            WindowedFingerprint(timestampMs: 4000, durationMs: 8000, hashes: [UInt32.max, 0])
        ]

        let data = try ReferenceFingerprintEncoder.encodeCompactV2(
            windows: windows,
            totalDurationSeconds: 30.5
        )

        let decoded = try XCTUnwrap(ReferenceFingerprint.decode(from: data))
        XCTAssertEqual(decoded.format, ReferenceFingerprint.supportedFormat)
        XCTAssertEqual(decoded.totalDuration, 30.5, accuracy: 0.0001)
        XCTAssertEqual(decoded.checkpointInterval, 2)
        XCTAssertEqual(decoded.checkpointDuration, 8)
        XCTAssertEqual(decoded.checkpointDurationSeconds, 8, accuracy: 0.0001)

        let checkpoints = decoded.libraryCheckpoints()
        XCTAssertEqual(checkpoints.count, windows.count)
        for (checkpoint, window) in zip(checkpoints, windows) {
            XCTAssertEqual(checkpoint.timestampSeconds, Float(window.timestampMs) / 1000, accuracy: 0.0001)
            XCTAssertEqual(checkpoint.hashes, window.hashes)
        }
    }

    func testEncodeRoundTripsUnsortedAndOffGridWindowsWithOneSecondQuantum() throws {
        // 3000 ms is not a multiple of the 2000 ms interval, so the encoder must fall
        // back to 1 s quantum units — and it must sort windows before delta-encoding.
        let windows = [
            WindowedFingerprint(timestampMs: 3000, durationMs: 8000, hashes: [7, 8]),
            WindowedFingerprint(timestampMs: 0, durationMs: 8000, hashes: [5, 6])
        ]

        let data = try ReferenceFingerprintEncoder.encodeCompactV2(
            windows: windows,
            totalDurationSeconds: 12
        )

        let decoded = try XCTUnwrap(ReferenceFingerprint.decode(from: data))
        XCTAssertEqual(decoded.timestampQuantum, 1)

        let checkpoints = decoded.libraryCheckpoints()
        XCTAssertEqual(checkpoints.count, 2)
        XCTAssertEqual(checkpoints[0].timestampSeconds, 0, accuracy: 0.0001)
        XCTAssertEqual(checkpoints[0].hashes, [5, 6])
        XCTAssertEqual(checkpoints[1].timestampSeconds, 3, accuracy: 0.0001)
        XCTAssertEqual(checkpoints[1].hashes, [7, 8])
    }

    // MARK: - Golden shape: exact field names / format string the decoder requires

    func testEncodedJSONHasExactCompactV2Shape() throws {
        let windows = [
            WindowedFingerprint(timestampMs: 0, durationMs: 8000, hashes: [0xDEADBEEF]),
            WindowedFingerprint(timestampMs: 2000, durationMs: 8000, hashes: [42])
        ]

        let data = try ReferenceFingerprintEncoder.encodeCompactV2(
            windows: windows,
            totalDurationSeconds: 60
        )

        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(
            Set(object.keys),
            ["format", "total_duration", "checkpoint_interval", "checkpoint_duration", "timestamp_quantum", "checkpoints"]
        )
        XCTAssertEqual(object["format"] as? String, "fingerprint-compact-v2")
        XCTAssertEqual(object["total_duration"] as? Double, 60)
        XCTAssertEqual(object["checkpoint_interval"] as? Int, 2)
        XCTAssertEqual(object["checkpoint_duration"] as? Int, 8)
        XCTAssertEqual(object["timestamp_quantum"] as? Int, 2)

        let checkpoints = try XCTUnwrap(object["checkpoints"] as? [[Any]])
        XCTAssertEqual(checkpoints.count, 2)
        for checkpoint in checkpoints {
            XCTAssertEqual(checkpoint.count, 2)
            XCTAssertNotNil(checkpoint[0] as? Int, "first element of a checkpoint pair must be the integer delta")
            let base64 = try XCTUnwrap(checkpoint[1] as? String)
            let payload = try XCTUnwrap(Data(base64Encoded: base64))
            XCTAssertEqual(payload.count % 4, 0, "hash payload must be whole little-endian UInt32s")
        }
        // Delta encoding on the 2 s grid with a 2 s quantum: first window at unit 0,
        // second one unit later.
        XCTAssertEqual(checkpoints[0][0] as? Int, 0)
        XCTAssertEqual(checkpoints[1][0] as? Int, 1)
    }

    func testEncodeWithNoWindowsStillDecodes() throws {
        let data = try ReferenceFingerprintEncoder.encodeCompactV2(
            windows: [],
            totalDurationSeconds: 5
        )

        let decoded = try XCTUnwrap(ReferenceFingerprint.decode(from: data))
        XCTAssertTrue(decoded.checkpoints.isEmpty)
        XCTAssertTrue(decoded.libraryCheckpoints().isEmpty)
    }

    // MARK: - Gzip round trip through the retriever's decompression path

    func testGzippedDataRoundTripsThroughRetrieverDecompression() throws {
        let windows = (0..<50).map { index in
            WindowedFingerprint(
                timestampMs: UInt32(index) * 2000,
                durationMs: 8000,
                hashes: (0..<20).map { UInt32(index * 31 + $0) }
            )
        }
        let json = try ReferenceFingerprintEncoder.encodeCompactV2(
            windows: windows,
            totalDurationSeconds: 120
        )

        let gzipped = try ReferenceFingerprintEncoder.gzipped(json)

        XCTAssertEqual(gzipped[gzipped.startIndex], 0x1f, "must be a real gzip container, not bare zlib/deflate")
        XCTAssertEqual(gzipped[gzipped.startIndex + 1], 0x8b)
        XCTAssertLessThan(gzipped.count, json.count, "fingerprint JSON should actually compress")

        let inflated = try XCTUnwrap(FingerprintReferenceRetriever.decompressGzipIfNeeded(gzipped))
        XCTAssertEqual(inflated, json)

        // And the inflated bytes still decode as a reference fingerprint.
        let decoded = try XCTUnwrap(ReferenceFingerprint.decode(from: inflated))
        XCTAssertEqual(decoded.checkpoints.count, windows.count)
    }

    // MARK: - Audio file → fingerprint integration

    /// No small audio fixture exists in the repo (and binary fixtures must not be
    /// added), so this test synthesizes a 12 s mono WAV at runtime and runs the real
    /// AVAudioFile → StreamingWindowedFingerprinter → encoder pipeline over it.
    func testFingerprintingSynthesizedAudioProducesNonDegenerateOutput() async throws {
        let url = try Self.makeNoiseWAV(seconds: 12)
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try await ReferenceFingerprintEncoder.fingerprint(audioFileURL: url)

        let decoded = try XCTUnwrap(ReferenceFingerprint.decode(from: data))
        XCTAssertEqual(decoded.format, ReferenceFingerprint.supportedFormat)
        XCTAssertEqual(decoded.totalDuration, 12, accuracy: 0.1)
        XCTAssertEqual(decoded.checkpointDuration, 8)
        XCTAssertEqual(decoded.checkpointInterval, 2)

        let checkpoints = decoded.libraryCheckpoints()
        // 12 s of audio with 8 s windows on a 2 s grid: at least the full windows at
        // 0 s, 2 s and 4 s must exist (flush may add trailing partials).
        XCTAssertGreaterThanOrEqual(checkpoints.count, 3)

        var previous: Float = -1
        for checkpoint in checkpoints {
            XCTAssertGreaterThan(checkpoint.timestampSeconds, previous, "timestamps must be strictly increasing")
            previous = checkpoint.timestampSeconds
            XCTAssertLessThanOrEqual(checkpoint.timestampSeconds, 12)
        }

        let totalHashes = checkpoints.reduce(0) { $0 + $1.hashes.count }
        XCTAssertGreaterThan(totalHashes, 0, "noise+tone audio must produce at least some hashes")
    }

    func testFingerprintThrowsCancellationErrorWhenAlreadyCancelled() async throws {
        let url = try Self.makeNoiseWAV(seconds: 1)
        defer { try? FileManager.default.removeItem(at: url) }

        let gate = CancellationGate()
        let task = Task<Data, Error> {
            await gate.wait()
            return try await ReferenceFingerprintEncoder.fingerprint(audioFileURL: url)
        }
        task.cancel()
        await gate.open()

        do {
            _ = try await task.value
            XCTFail("expected CancellationError")
        } catch {
            XCTAssertTrue(error is CancellationError, "expected CancellationError, got \(error)")
        }
    }

    // MARK: - Helpers

    /// Write a deterministic pseudo-noise + warbling-tone mono WAV. Noise gives the
    /// spectral peaks a landmark hasher needs; the tone keeps it non-stationary.
    private static func makeNoiseWAV(seconds: Double, sampleRate: Double = 44100) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fingerprint-encoder-test-\(UUID().uuidString).wav")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        let frames = AVAudioFrameCount(seconds * sampleRate)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
           let samples = buffer.floatChannelData?[0] else {
            throw NSError(domain: "ReferenceFingerprintEncoderTests", code: 1)
        }

        var state: UInt64 = 0x9E3779B97F4A7C15
        for i in 0..<Int(frames) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let noise = Float(Int32(truncatingIfNeeded: state >> 40)) / Float(1 << 23) - 1.0
            let t = Double(i) / sampleRate
            let tone = 0.4 * sin(2 * .pi * (440 + 220 * sin(2 * .pi * 0.5 * t)) * t)
            samples[i] = 0.5 * noise + Float(tone)
        }
        buffer.frameLength = frames

        try file.write(from: buffer)
        file.close()
        return url
    }
}

private actor CancellationGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}
