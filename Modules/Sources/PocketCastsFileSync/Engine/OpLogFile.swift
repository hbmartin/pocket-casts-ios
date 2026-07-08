import Foundation
import SwiftProtobuf

/// Reads and writes op log files: a sequence of `[varint length][OpEnvelope]`
/// records, the standard protobuf length-delimited framing.
///
/// Reading is corruption-tolerant: cloud providers can surface partially
/// propagated files, so a truncated final record is treated as
/// end-of-usable-data rather than an error. Anything before the truncation
/// point is returned.
public enum OpLogFile {
    public struct ReadResult: Sendable {
        public let envelopes: [Filesync_OpEnvelope]
        /// True when the file ended mid-record; the caller should retry the
        /// tail after the provider finishes propagating the file.
        public let truncated: Bool
    }

    public enum FramingError: Error {
        /// A varint length prefix ran past the protocol limit (corrupt file,
        /// not just truncation).
        case malformedLength(offset: Int)
    }

    /// Maximum size of a single framed record. Ops are small; anything
    /// claiming to be bigger than this is corruption, not data.
    public static let maxRecordBytes = 4 * 1024 * 1024

    // MARK: Encoding

    public static func encode(_ envelopes: [Filesync_OpEnvelope]) throws -> Data {
        var data = Data()
        for envelope in envelopes {
            let body = try envelope.serializedData()
            data.append(varint(UInt64(body.count)))
            data.append(body)
        }
        return data
    }

    public static func append(_ envelopes: [Filesync_OpEnvelope], to data: inout Data) throws {
        try data.append(encode(envelopes))
    }

    // MARK: Decoding

    /// Decodes every complete record in `data`. A cleanly truncated tail
    /// (incomplete varint or incomplete record body at end-of-data) sets
    /// `truncated` instead of throwing; a nonsensical length prefix throws.
    public static func decode(_ data: Data) throws -> ReadResult {
        var envelopes: [Filesync_OpEnvelope] = []
        // Data slices can have a non-zero startIndex; normalise offsets.
        let bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            guard let (length, lengthSize) = readVarint(bytes, at: offset) else {
                // Incomplete varint at the very end of the file.
                return ReadResult(envelopes: envelopes, truncated: true)
            }
            guard length <= UInt64(maxRecordBytes) else {
                throw FramingError.malformedLength(offset: offset)
            }
            let bodyStart = offset + lengthSize
            let bodyEnd = bodyStart + Int(length)
            guard bodyEnd <= bytes.count else {
                return ReadResult(envelopes: envelopes, truncated: true)
            }
            let body = Data(bytes[bodyStart ..< bodyEnd])
            do {
                envelopes.append(try Filesync_OpEnvelope(serializedBytes: body))
            } catch {
                // A record that fails to parse but is fully framed is
                // corruption; stop here but keep what we have.
                return ReadResult(envelopes: envelopes, truncated: true)
            }
            offset = bodyEnd
        }
        return ReadResult(envelopes: envelopes, truncated: false)
    }

    /// Decodes records starting at a byte offset (a reader cursor from a
    /// previous pass), returning the new offset alongside the records.
    public static func decode(_ data: Data, fromOffset startOffset: Int) throws -> (result: ReadResult, nextOffset: Int) {
        guard startOffset < data.count else {
            return (ReadResult(envelopes: [], truncated: false), startOffset)
        }
        let tail = data.subdata(in: startOffset ..< data.count)
        let result = try decode(tail)
        if result.truncated {
            // Only count the fully consumed records towards the new offset.
            let consumed = try encode(result.envelopes).count
            return (result, startOffset + consumed)
        }
        return (result, data.count)
    }

    // MARK: Varint

    static func varint(_ value: UInt64) -> Data {
        var value = value
        var data = Data()
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            data.append(byte)
        } while value != 0
        return data
    }

    static func readVarint(_ bytes: [UInt8], at offset: Int) -> (value: UInt64, size: Int)? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        var size = 0
        while offset + size < bytes.count, size < 10 {
            let byte = bytes[offset + size]
            value |= UInt64(byte & 0x7F) << shift
            size += 1
            if byte & 0x80 == 0 {
                return (value, size)
            }
            shift += 7
        }
        return nil
    }
}
