import AVFoundation
import Compression
import Foundation
@preconcurrency import Fingerprint

/// Encoder for the `fingerprint-compact-v2` reference-fingerprint format — the exact
/// inverse of `ReferenceFingerprint`. Used by the transcript-contribution pipeline to
/// upload a fingerprint of the exact audio file a transcription was cut from
/// (`docs/TranscriptContributions.md` §2–3).
///
/// The contract is round-trip fidelity with `ReferenceFingerprint.decode(from:)`:
/// whatever this encoder emits must decode into identical checkpoints/config. Note the
/// decoder's units — `checkpoint_interval`, `checkpoint_duration` and `timestamp_quantum`
/// are **seconds** (`checkpointDurationSeconds` is `Float(checkpointDuration)` and a
/// checkpoint's timestamp is `accumulatedDelta * timestampQuantum` seconds), so this
/// encoder writes seconds too, even though `docs/Fingerprinting.md`'s example comments
/// say "ms".
nonisolated enum ReferenceFingerprintEncoder {

    /// Duration of each encoded checkpoint window. Mirrors the server reference's
    /// `checkpoint_duration` (8 s) — the same value the live matcher uses for its own
    /// windows (`FingerprintConstants.windowDurationMs`), because live windows must be
    /// the same length as reference checkpoints to score against them.
    static let canonicalWindowDurationMs: UInt32 = FingerprintConstants.windowDurationMs

    /// Interval between encoded checkpoint windows: the reference's 2 s checkpoint grid.
    /// Deliberately NOT `FingerprintConstants.windowIntervalMs` (1000): that constant is
    /// the live-matching stride, documented in-source as "deliberately FINER than the
    /// reference's 2s checkpoint grid" (oversampling). A fingerprint we upload becomes a
    /// *reference*, so it must sit on the same 2 s grid the consumer-side matcher
    /// oversamples against.
    static let canonicalWindowIntervalMs: UInt32 = 2000

    enum EncoderError: Error {
        /// The audio produced no fingerprint windows (e.g. empty or unreadable PCM).
        case noWindows
        /// The audio file reports a non-positive sample rate or zero channels.
        case invalidAudioFormat
        /// A PCM chunk buffer could not be allocated.
        case bufferAllocationFailed
        /// Deflate compression failed (or the payload was empty).
        case gzipFailed
    }

    // MARK: - JSON Encoding

    /// Serialize fingerprint windows to `fingerprint-compact-v2` JSON.
    ///
    /// Checkpoint timestamps are delta-encoded in `timestamp_quantum`-second units:
    /// when every window sits on the `windowIntervalMs` grid (the normal case — the
    /// streamer emits windows at exact interval multiples) the quantum is the interval
    /// in whole seconds; otherwise it falls back to 1 s units with rounding.
    static func encodeCompactV2(
        windows: [WindowedFingerprint],
        totalDurationSeconds: Double,
        windowDurationMs: UInt32 = canonicalWindowDurationMs,
        windowIntervalMs: UInt32 = canonicalWindowIntervalMs
    ) throws -> Data {
        let sorted = windows.sorted { $0.timestampMs < $1.timestampMs }

        let quantumSeconds: Int
        if windowIntervalMs >= 1000, windowIntervalMs % 1000 == 0,
           sorted.allSatisfy({ $0.timestampMs % windowIntervalMs == 0 }) {
            quantumSeconds = Int(windowIntervalMs / 1000)
        } else {
            quantumSeconds = 1
        }

        var checkpoints: [CompactV2.Checkpoint] = []
        checkpoints.reserveCapacity(sorted.count)
        var previousUnits = 0
        for window in sorted {
            let seconds = Double(window.timestampMs) / 1000.0
            let units = Int((seconds / Double(quantumSeconds)).rounded())
            let delta = units - previousUnits
            // Two windows quantized into the same slot: keep the first only, so
            // decoded timestamps stay strictly increasing.
            if delta == 0, !checkpoints.isEmpty { continue }
            previousUnits = units
            checkpoints.append(CompactV2.Checkpoint(
                delta: delta,
                data: packedLittleEndian(window.hashes).base64EncodedString()
            ))
        }

        let payload = CompactV2(
            format: ReferenceFingerprint.supportedFormat,
            totalDuration: totalDurationSeconds,
            checkpointInterval: Int(windowIntervalMs / 1000),
            checkpointDuration: Int(windowDurationMs / 1000),
            timestampQuantum: quantumSeconds,
            checkpoints: checkpoints
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    // MARK: - Audio → Fingerprint

    /// Stream-decode `audioFileURL` and produce its `fingerprint-compact-v2` JSON.
    ///
    /// Mirrors `FingerprintTimingManager`'s streaming pass: `AVAudioFile` is forced to
    /// hand back non-interleaved Float32 PCM at the file's native sample rate/channel
    /// count (the Rust `StreamingWindowedFingerprinter` takes those as constructor
    /// arguments and handles them internally), read in
    /// `FingerprintConstants.streamChunkSeconds` chunks so the whole file is never
    /// resident in memory, and interleaved before each push. Cancellation is checked
    /// once per chunk.
    ///
    /// Returns plain (un-gzipped) JSON; wrap with `gzipped(_:)` for upload.
    @concurrent
    static func fingerprint(audioFileURL: URL) async throws -> Data {
        try Task.checkCancellation()

        let audioFile = try AVAudioFile(
            forReading: audioFileURL,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let format = audioFile.processingFormat
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw EncoderError.invalidAudioFormat
        }
        let channels = UInt16(format.channelCount)
        let totalDurationSeconds = Double(audioFile.length) / format.sampleRate

        let streamer = StreamingWindowedFingerprinter(
            sampleRate: UInt32(format.sampleRate),
            channels: channels,
            windowDurationMs: canonicalWindowDurationMs,
            windowIntervalMs: canonicalWindowIntervalMs
        )

        let chunkFrames = AVAudioFrameCount(format.sampleRate * FingerprintConstants.streamChunkSeconds)
        guard chunkFrames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw EncoderError.bufferAllocationFailed
        }

        var windows: [WindowedFingerprint] = []
        // Bound on framePosition rather than reading to an empty buffer: a read
        // issued after EOF throws AVFoundation's bare "nilError" on some
        // containers (WAV among them) instead of returning zero frames.
        while audioFile.framePosition < audioFile.length {
            try Task.checkCancellation()
            try audioFile.read(into: buffer, frameCount: chunkFrames)
            if buffer.frameLength == 0 { break }

            let interleaved = interleavedSamples(from: buffer)
            windows.append(contentsOf: streamer.pushSamplesF32(samples: interleaved, channels: channels))
        }

        try Task.checkCancellation()
        windows.append(contentsOf: streamer.flush())

        guard !windows.isEmpty else { throw EncoderError.noWindows }
        return try encodeCompactV2(windows: windows, totalDurationSeconds: totalDurationSeconds)
    }

    // MARK: - Gzip

    /// Compress `data` into a gzip container (RFC 1952) suitable for the upload body.
    ///
    /// Container choice: a *real* gzip member, not a bare zlib/deflate stream. The
    /// server serves references as `.json.gz`, and the client's own decompression path
    /// (`FingerprintReferenceRetriever.decompressGzipIfNeeded`) requires the
    /// `0x1f 0x8b` magic, strips the 10-byte gzip header and 8-byte trailer, then
    /// inflates the raw-deflate body with `COMPRESSION_ZLIB` — which is exactly what
    /// `compression_encode_buffer(COMPRESSION_ZLIB)` emits (raw deflate, no zlib
    /// framing). So header + deflate + CRC32/ISIZE trailer round-trips through the
    /// same code the retriever uses.
    static func gzipped(_ data: Data) throws -> Data {
        guard !data.isEmpty else { throw EncoderError.gzipFailed }

        let deflated = try deflate(data)

        var output = Data(capacity: deflated.count + 18)
        // Header: magic, deflate method, no flags, zero mtime, no extra flags, OS = Unix.
        output.append(contentsOf: [0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03])
        output.append(deflated)

        var trailer = [UInt8](repeating: 0, count: 8)
        let crc = crc32(data)
        let isize = UInt32(truncatingIfNeeded: data.count)
        for i in 0..<4 {
            trailer[i] = UInt8((crc >> (8 * UInt32(i))) & 0xff)
            trailer[i + 4] = UInt8((isize >> (8 * UInt32(i))) & 0xff)
        }
        output.append(contentsOf: trailer)
        return output
    }

    // MARK: - Private helpers

    /// Mirror of the decoder's expectation in `ReferenceFingerprint.libraryCheckpoints()`:
    /// the `data` payload is the raw little-endian byte packing of `[UInt32]` hashes.
    private static func packedLittleEndian(_ hashes: [UInt32]) -> Data {
        var payload = Data(capacity: hashes.count * MemoryLayout<UInt32>.size)
        for hash in hashes {
            withUnsafeBytes(of: hash.littleEndian) { payload.append(contentsOf: $0) }
        }
        return payload
    }

    /// Same conversion `FingerprintTimingManager.interleavedSamples(from:)` performs
    /// before pushing PCM into the streamer (that helper is private to the manager).
    private static func interleavedSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0,
              let channelData = buffer.floatChannelData else { return [] }

        if channelCount == 1 {
            return Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        }

        var result = [Float](repeating: 0, count: frameCount * channelCount)
        for ch in 0..<channelCount {
            let src = channelData[ch]
            for frame in 0..<frameCount {
                result[frame * channelCount + ch] = src[frame]
            }
        }
        return result
    }

    /// Raw-deflate `data` with the Compression framework (`COMPRESSION_ZLIB` encode
    /// emits a raw DEFLATE stream — no zlib header/checksum — which is what a gzip
    /// member body wraps).
    private static func deflate(_ data: Data) throws -> Data {
        // Worst case (incompressible input) deflate grows by ~5 bytes per 64 KiB
        // stored block plus a few bytes; count/2 + 64 comfortably covers it.
        let capacity = data.count + data.count / 2 + 64
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destination.deallocate() }

        let written = data.withUnsafeBytes { rawBuffer -> Int in
            guard let base = rawBuffer.baseAddress else { return 0 }
            return compression_encode_buffer(
                destination,
                capacity,
                base.assumingMemoryBound(to: UInt8.self),
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard written > 0 else { throw EncoderError.gzipFailed }
        return Data(bytes: destination, count: written)
    }

    private static let crc32Table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) != 0 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = crc32Table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    /// Encodable mirror of `ReferenceFingerprint` — field names and the unkeyed
    /// `[delta, data]` checkpoint shape must stay byte-for-byte compatible with the
    /// decoder's `CodingKeys` / `Checkpoint.init(from:)`.
    private struct CompactV2: Encodable {
        let format: String
        let totalDuration: Double
        let checkpointInterval: Int
        let checkpointDuration: Int
        let timestampQuantum: Int
        let checkpoints: [Checkpoint]

        enum CodingKeys: String, CodingKey {
            case format
            case totalDuration = "total_duration"
            case checkpointInterval = "checkpoint_interval"
            case checkpointDuration = "checkpoint_duration"
            case timestampQuantum = "timestamp_quantum"
            case checkpoints
        }

        struct Checkpoint: Encodable {
            let delta: Int
            let data: String

            func encode(to encoder: Encoder) throws {
                var container = encoder.unkeyedContainer()
                try container.encode(delta)
                try container.encode(data)
            }
        }
    }
}
