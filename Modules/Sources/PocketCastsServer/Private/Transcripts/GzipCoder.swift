import Compression
import Foundation

/// Minimal gzip (RFC 1952) encode/decode built on the Compression framework.
///
/// Apple's `COMPRESSION_ZLIB` produces/consumes a raw DEFLATE stream, so this
/// wraps it in the gzip container (10-byte header + CRC32/ISIZE trailer). Used
/// for the transcript contribution request bodies (`Content-Encoding: gzip`);
/// no other task in this module gzips today. Decoding exists so tests can
/// round-trip the exact bytes that go on the wire.
enum GzipCoder {
    enum GzipError: Error {
        case encodingFailed
        case notGzip
        case truncated
        case decodingFailed
        case checksumMismatch
    }

    private static let headerSize = 10
    private static let trailerSize = 8

    /// Gzip-compresses `data`. The output starts with the standard magic bytes
    /// `0x1f 0x8b` and ends with the CRC32 + ISIZE trailer.
    static func gzip(_ data: Data) throws -> Data {
        var output = Data([
            0x1f, 0x8b, // magic
            0x08, // CM = deflate
            0x00, // FLG = none
            0x00, 0x00, 0x00, 0x00, // MTIME = 0 (deterministic bodies; assertion signs the bytes)
            0x00, // XFL
            0xff // OS = unknown
        ])
        output.append(try rawDeflate(data))
        output.append(littleEndianBytes(of: crc32(data)))
        output.append(littleEndianBytes(of: UInt32(truncatingIfNeeded: data.count)))
        return output
    }

    /// Inflates a gzip stream produced by `gzip(_:)` or any RFC 1952 encoder,
    /// verifying the CRC32 and length trailer.
    static func gunzip(_ data: Data) throws -> Data {
        // Index relative to the start of the (possibly sliced) data.
        let bytes = Data(data)
        guard bytes.count >= headerSize + trailerSize else { throw GzipError.truncated }
        guard bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 0x08 else { throw GzipError.notGzip }

        let flags = bytes[3]
        var offset = headerSize
        if flags & 0x04 != 0 { // FEXTRA
            guard bytes.count > offset + 2 else { throw GzipError.truncated }
            let extraLength = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2 + extraLength
        }
        if flags & 0x08 != 0 { // FNAME: zero-terminated
            offset = try indexPastZeroTerminator(in: bytes, from: offset)
        }
        if flags & 0x10 != 0 { // FCOMMENT: zero-terminated
            offset = try indexPastZeroTerminator(in: bytes, from: offset)
        }
        if flags & 0x02 != 0 { // FHCRC
            offset += 2
        }
        guard bytes.count >= offset + trailerSize else { throw GzipError.truncated }

        let deflated = bytes.subdata(in: offset ..< (bytes.count - trailerSize))
        let trailer = bytes.suffix(trailerSize)
        let expectedCrc = littleEndianUInt32(Data(trailer.prefix(4)))
        let expectedSize = littleEndianUInt32(Data(trailer.suffix(4)))

        let inflated = try rawInflate(deflated, sizeHint: Int(expectedSize))
        guard UInt32(truncatingIfNeeded: inflated.count) == expectedSize,
              crc32(inflated) == expectedCrc
        else {
            throw GzipError.checksumMismatch
        }
        return inflated
    }

    // MARK: - Raw DEFLATE via Compression

    private static func rawDeflate(_ data: Data) throws -> Data {
        // DEFLATE of an empty input is a single empty stored/final block; the
        // buffer API can't express it, so special-case it.
        guard !data.isEmpty else { return Data([0x03, 0x00]) }

        // Deflate never usefully exceeds input size by much; give generous slack
        // for tiny/incompressible inputs.
        let capacity = data.count + max(64, data.count / 16)
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
                compression_encode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { throw GzipError.encodingFailed }
        return output.prefix(written)
    }

    private static func rawInflate(_ data: Data, sizeHint: Int) throws -> Data {
        guard !data.isEmpty else { throw GzipError.truncated }
        // Clamp the ISIZE-derived allocation: request bodies are capped at 3 MB
        // (docs/TranscriptContributions.md §4), so 64 MB is generous; a lying
        // trailer then fails the length/CRC check instead of exhausting memory.
        let capacity = min(max(sizeHint, 64), 64 * 1024 * 1024)
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        // A result equal to capacity can mean the output was truncated to fit;
        // the ISIZE check in gunzip(_:) catches any mismatch.
        guard written > 0 || sizeHint == 0 else { throw GzipError.decodingFailed }
        return output.prefix(written)
    }

    // MARK: - CRC32 (IEEE, as used by gzip)

    private static let crcTable: [UInt32] = (0 ..< 256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0 ..< 8 {
            value = (value & 1) == 1 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    // MARK: - Little-endian helpers

    private static func littleEndianBytes(of value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static func littleEndianUInt32(_ data: Data) -> UInt32 {
        precondition(data.count == 4)
        return UInt32(littleEndian: data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
    }

    private static func indexPastZeroTerminator(in data: Data, from start: Int) throws -> Int {
        var index = start
        while index < data.count {
            if data[index] == 0 { return index + 1 }
            index += 1
        }
        throw GzipError.truncated
    }
}
