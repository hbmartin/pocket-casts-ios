import Foundation

/// A single chapter parsed from an ID3v2 tag's `CHAP` frame.
public struct ID3Chapter: Equatable, Sendable {
    /// The `CHAP` frame's element ID, used by `CTOC` frames to reference the chapter.
    public let elementID: String

    /// The chapter title from an embedded `TIT2` sub-frame, if present.
    public let title: String?

    /// Chapter start, in milliseconds from the start of the audio.
    public let startTimeMs: UInt32

    /// Chapter end, in milliseconds from the start of the audio.
    public let endTimeMs: UInt32

    /// Raw image bytes from an embedded `APIC` sub-frame, if present.
    public let artworkData: Data?

    /// The MIME type declared by the `APIC` sub-frame, if present.
    public let artworkMimeType: String?

    /// A chapter link from an embedded `WXXX` sub-frame, if present.
    public let url: String?

    /// `true` when the tag has a table of contents (`CTOC`) that does not list this chapter.
    /// When every chapter ends up hidden the caller should treat them all as visible.
    public let isHidden: Bool
}

/// A pure, defensive parser for chapters embedded in ID3v2.3 / ID3v2.4 tags (`CHAP` + `CTOC` frames).
///
/// Every read is bounds-checked: malformed or truncated input yields whatever was successfully
/// parsed before the damage (possibly an empty array), never a crash.
///
/// Ordering rules for the returned chapters:
/// - When a `CTOC` frame is present (the first top-level one wins, falling back to the first seen),
///   chapters it lists come first, in the table-of-contents order. Chapters it does not list are
///   marked ``ID3Chapter/isHidden`` and appended afterwards, sorted by start time.
/// - Without a `CTOC`, chapters are sorted by start time (ties keep their appearance order).
public enum ID3ChapterParser {
    /// The fixed length of an ID3v2 tag header (and of the optional v2.4 footer).
    public static let tagHeaderLength = 10

    /// Reads an ID3v2 tag header and returns the total tag length in bytes (header + body + optional
    /// footer), so callers can fetch exactly the tag's bytes before calling ``parseChapters(from:)``.
    /// Returns nil when `data` does not start with a plausible ID3v2.2–2.4 header.
    public static func declaredTagLength(fromHeader data: Data) -> Int? {
        TagHeader(bytes: [UInt8](data.prefix(tagHeaderLength)))?.totalTagLength
    }

    /// Parses the `CHAP`/`CTOC` chapter frames out of data that begins with an ID3v2 tag.
    /// Returns an empty array when there is no leading ID3v2.3/2.4 tag or no chapters.
    public static func parseChapters(from data: Data) -> [ID3Chapter] {
        let bytes = [UInt8](data)
        guard let header = TagHeader(bytes: Array(bytes.prefix(tagHeaderLength))) else { return [] }

        // CHAP/CTOC were introduced alongside v2.3; v2.2 tags can't contain chapters.
        guard header.majorVersion == 3 || header.majorVersion == 4 else { return [] }

        // Tolerate truncation: parse whatever portion of the declared body is actually present.
        let bodyEnd = min(bytes.count, tagHeaderLength + header.bodyLength)
        guard bodyEnd > tagHeaderLength else { return [] }
        var body = Array(bytes[tagHeaderLength ..< bodyEnd])

        // v2.3 applies unsynchronisation to the whole tag body; v2.4 applies it per-frame.
        if header.isUnsynchronised, header.majorVersion == 3 {
            body = removeUnsynchronisation(body)
        }

        var reader = ByteReader(body)
        if header.hasExtendedHeader {
            guard skipExtendedHeader(&reader, majorVersion: header.majorVersion) else { return [] }
        }

        var rawChapters = [RawChapter]()
        var tablesOfContents = [TableOfContents]()
        while let frame = readFrame(&reader, majorVersion: header.majorVersion, tagUnsynchronised: header.isUnsynchronised) {
            switch frame.id {
            case "CHAP":
                if let chapter = parseChapterFrame(frame.content, majorVersion: header.majorVersion) {
                    rawChapters.append(chapter)
                }
            case "CTOC":
                if let toc = parseTableOfContentsFrame(frame.content) {
                    tablesOfContents.append(toc)
                }
            default:
                break
            }
        }

        let tableOfContents = tablesOfContents.first(where: \.isTopLevel) ?? tablesOfContents.first
        return assembleChapters(rawChapters, tableOfContents: tableOfContents)
    }

    // MARK: - Tag header

    private struct TagHeader {
        let majorVersion: UInt8
        let isUnsynchronised: Bool
        let hasExtendedHeader: Bool
        let hasFooter: Bool
        let bodyLength: Int

        var totalTagLength: Int {
            ID3ChapterParser.tagHeaderLength + bodyLength + (hasFooter ? ID3ChapterParser.tagHeaderLength : 0)
        }

        init?(bytes: [UInt8]) {
            guard bytes.count >= ID3ChapterParser.tagHeaderLength,
                  bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33, // "ID3"
                  (2 ... 4).contains(bytes[3]), bytes[4] != 0xFF,
                  bytes[6] < 0x80, bytes[7] < 0x80, bytes[8] < 0x80, bytes[9] < 0x80
            else { return nil }

            majorVersion = bytes[3]
            let flags = bytes[5]
            isUnsynchronised = flags & 0x80 != 0
            hasExtendedHeader = flags & 0x40 != 0
            hasFooter = majorVersion >= 4 && flags & 0x10 != 0
            bodyLength = ID3ChapterParser.syncsafeValue(bytes[6 ... 9])
        }
    }

    /// Skips over the extended header, whose layout differs between versions:
    /// v2.3 declares a plain 4-byte size that excludes the size field itself, v2.4 declares a
    /// syncsafe size that includes the whole extended header.
    private static func skipExtendedHeader(_ reader: inout ByteReader, majorVersion: UInt8) -> Bool {
        guard let sizeBytes = reader.readBytes(4) else { return false }
        if majorVersion >= 4 {
            let totalSize = syncsafeValue(sizeBytes)
            guard totalSize >= 4 else { return false }
            return reader.skipBytes(totalSize - 4)
        } else {
            return reader.skipBytes(plainValue(sizeBytes))
        }
    }

    // MARK: - Frames

    private struct RawFrame {
        let id: String
        let content: [UInt8]
    }

    /// Reads one frame header + content. Returns nil at padding, truncation, or a corrupt frame ID,
    /// which ends parsing at the current level.
    private static func readFrame(_ reader: inout ByteReader, majorVersion: UInt8, tagUnsynchronised: Bool) -> RawFrame? {
        // A zero byte where a frame ID should start means the rest of the tag is padding.
        guard let firstByte = reader.peekByte(), firstByte != 0 else { return nil }
        guard let idBytes = reader.readBytes(4),
              idBytes.allSatisfy({ ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x30 && $0 <= 0x39) }) // A-Z / 0-9
        else { return nil }
        let id = String(decoding: idBytes, as: UTF8.self)

        guard let sizeBytes = reader.readBytes(4) else { return nil }
        let size: Int
        if majorVersion >= 4 {
            // v2.4 sizes are syncsafe; some real-world encoders wrongly write plain sizes, which are
            // recognisable by a set high bit.
            size = sizeBytes.allSatisfy { $0 < 0x80 } ? syncsafeValue(sizeBytes) : plainValue(sizeBytes)
        } else {
            size = plainValue(sizeBytes)
        }

        guard let flagBytes = reader.readBytes(2), var content = reader.readBytes(size) else { return nil }
        let formatFlags = flagBytes[1]

        if majorVersion >= 4 {
            if formatFlags & 0x08 != 0 || formatFlags & 0x04 != 0 {
                // Compressed or encrypted frames can't be parsed here; skip the content but keep going.
                return RawFrame(id: id, content: [])
            }
            if formatFlags & 0x02 != 0 || tagUnsynchronised {
                content = removeUnsynchronisation(content)
            }
            if formatFlags & 0x40 != 0 { content.removeFirst(min(1, content.count)) } // grouping identity byte
            if formatFlags & 0x01 != 0 { content.removeFirst(min(4, content.count)) } // data length indicator
        } else {
            if formatFlags & 0x80 != 0 || formatFlags & 0x40 != 0 {
                return RawFrame(id: id, content: []) // compressed / encrypted
            }
            if formatFlags & 0x20 != 0 { content.removeFirst(min(1, content.count)) } // grouping identity byte
        }

        return RawFrame(id: id, content: content)
    }

    // MARK: - CHAP

    private struct RawChapter {
        let elementID: String
        let startTimeMs: UInt32
        let endTimeMs: UInt32
        let title: String?
        let artworkData: Data?
        let artworkMimeType: String?
        let url: String?

        func chapter(isHidden: Bool) -> ID3Chapter {
            ID3Chapter(elementID: elementID, title: title, startTimeMs: startTimeMs, endTimeMs: endTimeMs,
                       artworkData: artworkData, artworkMimeType: artworkMimeType, url: url, isHidden: isHidden)
        }
    }

    /// CHAP layout: element ID (latin-1, null-terminated), start ms, end ms, start byte offset,
    /// end byte offset (each 4 bytes big-endian), then optional embedded sub-frames.
    private static func parseChapterFrame(_ content: [UInt8], majorVersion: UInt8) -> RawChapter? {
        var reader = ByteReader(content)
        guard let elementIDBytes = reader.readNullTerminated(),
              let startTimeMs = reader.readUInt32BE(),
              let endTimeMs = reader.readUInt32BE()
        else { return nil }
        _ = reader.skipBytes(8) // byte offsets; podcast chapters set them to 0xFFFFFFFF ("use the times")

        var title: String?
        var artworkData: Data?
        var artworkMimeType: String?
        var url: String?
        while let subFrame = readFrame(&reader, majorVersion: majorVersion, tagUnsynchronised: false) {
            switch subFrame.id {
            case "TIT2" where title == nil:
                title = parseTextFrame(subFrame.content)
            case "APIC" where artworkData == nil:
                (artworkData, artworkMimeType) = parseAttachedPictureFrame(subFrame.content)
            case "WXXX" where url == nil:
                url = parseUserURLFrame(subFrame.content)
            default:
                break
            }
        }

        return RawChapter(elementID: String(bytes: elementIDBytes, encoding: .isoLatin1) ?? "",
                          startTimeMs: startTimeMs, endTimeMs: endTimeMs,
                          title: title, artworkData: artworkData, artworkMimeType: artworkMimeType, url: url)
    }

    // MARK: - CTOC

    private struct TableOfContents {
        let isTopLevel: Bool
        let childElementIDs: [String]
    }

    /// CTOC layout: element ID (null-terminated), flags (bit 1 = top-level, bit 0 = ordered),
    /// entry count, then entry-count null-terminated child element IDs.
    private static func parseTableOfContentsFrame(_ content: [UInt8]) -> TableOfContents? {
        var reader = ByteReader(content)
        guard reader.readNullTerminated() != nil, // element ID of the TOC itself
              let flags = reader.readByte(),
              let entryCount = reader.readByte()
        else { return nil }

        var childElementIDs = [String]()
        if entryCount > 0 {
            for _ in 0 ..< entryCount {
                guard let idBytes = reader.readNullTerminated() else { break }
                childElementIDs.append(String(bytes: idBytes, encoding: .isoLatin1) ?? "")
            }
        } else {
            // Lenient fallback for broken writers that leave the count at 0: treat every remaining
            // null-terminated run as a child ID (mirrors the old MNAVChapterReader behaviour).
            while let idBytes = reader.readNullTerminated() {
                childElementIDs.append(String(bytes: idBytes, encoding: .isoLatin1) ?? "")
            }
        }

        return TableOfContents(isTopLevel: flags & 0x02 != 0, childElementIDs: childElementIDs)
    }

    // MARK: - Sub-frame payloads

    /// Text frame (TIT2 etc.): encoding byte + text in that encoding, optionally null-terminated.
    private static func parseTextFrame(_ content: [UInt8]) -> String? {
        guard let encodingByte = content.first else { return nil }
        return decodeText(Array(content.dropFirst()), encodingByte: encodingByte)
    }

    /// APIC: encoding byte, MIME type (latin-1, null-terminated), picture type byte,
    /// description (terminated per the encoding), then the raw image bytes.
    private static func parseAttachedPictureFrame(_ content: [UInt8]) -> (data: Data?, mimeType: String?) {
        var reader = ByteReader(content)
        guard let encodingByte = reader.readByte(),
              let mimeBytes = reader.readNullTerminated(),
              reader.readByte() != nil, // picture type
              reader.skipTerminatedString(encodingByte: encodingByte) // description
        else { return (nil, nil) }

        let imageBytes = reader.readRemaining()
        let mimeType = String(bytes: mimeBytes, encoding: .isoLatin1)
        return (imageBytes.isEmpty ? nil : Data(imageBytes), mimeType)
    }

    /// WXXX: encoding byte, description (terminated per the encoding), then the URL (always latin-1).
    private static func parseUserURLFrame(_ content: [UInt8]) -> String? {
        var reader = ByteReader(content)
        guard let encodingByte = reader.readByte(),
              reader.skipTerminatedString(encodingByte: encodingByte)
        else { return nil }

        var urlBytes = reader.readRemaining()
        while urlBytes.last == 0 { urlBytes.removeLast() }
        guard !urlBytes.isEmpty else { return nil }
        return String(bytes: urlBytes, encoding: .isoLatin1)
    }

    // MARK: - Assembly

    private static func assembleChapters(_ rawChapters: [RawChapter], tableOfContents: TableOfContents?) -> [ID3Chapter] {
        // Stable sort by start time: ties keep appearance order.
        let sortedByStart = rawChapters.enumerated()
            .sorted { ($0.element.startTimeMs, $0.offset) < ($1.element.startTimeMs, $1.offset) }
            .map(\.element)

        guard let tableOfContents else {
            return sortedByStart.map { $0.chapter(isHidden: false) }
        }

        var tocPosition = [String: Int]()
        for (position, elementID) in tableOfContents.childElementIDs.enumerated() where tocPosition[elementID] == nil {
            tocPosition[elementID] = position
        }

        let listed = sortedByStart.enumerated()
            .compactMap { offset, chapter in tocPosition[chapter.elementID].map { ($0, offset, chapter) } }
            .sorted { ($0.0, $0.1) < ($1.0, $1.1) }
            .map { $0.2.chapter(isHidden: false) }
        let unlisted = sortedByStart
            .filter { tocPosition[$0.elementID] == nil }
            .map { $0.chapter(isHidden: true) }
        return listed + unlisted
    }

    // MARK: - Text decoding

    /// ID3v2 text encodings: 0 = ISO-8859-1, 1 = UTF-16 with BOM, 2 = UTF-16BE, 3 = UTF-8.
    private static func decodeText(_ bytes: [UInt8], encodingByte: UInt8) -> String? {
        switch encodingByte {
        case 1:
            let cut = cutAtDoubleNull(bytes)
            return String(bytes: cut, encoding: .utf16) ?? String(bytes: cut, encoding: .utf16LittleEndian)
        case 2:
            return String(bytes: cutAtDoubleNull(bytes), encoding: .utf16BigEndian)
        case 3:
            return String(bytes: cutAtSingleNull(bytes), encoding: .utf8)
        default:
            return String(bytes: cutAtSingleNull(bytes), encoding: .isoLatin1)
        }
    }

    private static func cutAtSingleNull(_ bytes: [UInt8]) -> [UInt8] {
        bytes.firstIndex(of: 0).map { Array(bytes[..<$0]) } ?? bytes
    }

    /// Cuts at the first 16-bit-aligned 0x0000 pair (the UTF-16 terminator).
    private static func cutAtDoubleNull(_ bytes: [UInt8]) -> [UInt8] {
        var index = 0
        while index + 1 < bytes.count {
            if bytes[index] == 0, bytes[index + 1] == 0 {
                return Array(bytes[..<index])
            }
            index += 2
        }
        return bytes
    }

    // MARK: - Byte-level helpers

    /// Reverses ID3v2 unsynchronisation: every 0xFF 0x00 pair becomes a lone 0xFF.
    private static func removeUnsynchronisation(_ bytes: [UInt8]) -> [UInt8] {
        var result = [UInt8]()
        result.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            result.append(byte)
            index += 1
            if byte == 0xFF, index < bytes.count, bytes[index] == 0 {
                index += 1
            }
        }
        return result
    }

    /// Four 7-bit bytes, big-endian (high bit of each byte is always zero).
    private static func syncsafeValue(_ bytes: some Collection<UInt8>) -> Int {
        bytes.reduce(0) { ($0 << 7) | Int($1 & 0x7F) }
    }

    private static func plainValue(_ bytes: some Collection<UInt8>) -> Int {
        bytes.reduce(0) { ($0 << 8) | Int($1) }
    }

    /// A bounds-checked cursor over a byte array; every read returns nil instead of overrunning.
    private struct ByteReader {
        private let bytes: [UInt8]
        private var offset = 0

        init(_ bytes: [UInt8]) {
            self.bytes = bytes
        }

        func peekByte() -> UInt8? {
            offset < bytes.count ? bytes[offset] : nil
        }

        mutating func readByte() -> UInt8? {
            guard offset < bytes.count else { return nil }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func readBytes(_ count: Int) -> [UInt8]? {
            guard count >= 0, bytes.count - offset >= count else { return nil }
            defer { offset += count }
            return Array(bytes[offset ..< offset + count])
        }

        mutating func skipBytes(_ count: Int) -> Bool {
            guard count >= 0, bytes.count - offset >= count else { return false }
            offset += count
            return true
        }

        mutating func readUInt32BE() -> UInt32? {
            readBytes(4).map { $0.reduce(0) { ($0 << 8) | UInt32($1) } }
        }

        /// Reads up to (excluding) the next 0x00 and consumes the terminator.
        /// Returns nil when no terminator exists in the remaining bytes.
        mutating func readNullTerminated() -> [UInt8]? {
            guard offset < bytes.count, let terminator = bytes[offset...].firstIndex(of: 0) else { return nil }
            defer { offset = terminator + 1 }
            return Array(bytes[offset ..< terminator])
        }

        /// Skips a string terminated per the ID3 text encoding: a 16-bit-aligned 0x0000 pair for the
        /// UTF-16 encodings (1 and 2), a single 0x00 otherwise.
        mutating func skipTerminatedString(encodingByte: UInt8) -> Bool {
            if encodingByte == 1 || encodingByte == 2 {
                var index = offset
                while index + 1 < bytes.count {
                    if bytes[index] == 0, bytes[index + 1] == 0 {
                        offset = index + 2
                        return true
                    }
                    index += 2
                }
                return false
            }
            return readNullTerminated() != nil
        }

        mutating func readRemaining() -> [UInt8] {
            defer { offset = bytes.count }
            return Array(bytes[offset...])
        }
    }
}
