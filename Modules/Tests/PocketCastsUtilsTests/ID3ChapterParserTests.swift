import Foundation
import PocketCastsUtils
import XCTest

final class ID3ChapterParserTests: XCTestCase {
    // MARK: - Basic parsing

    func testEmptyDataReturnsNoChapters() {
        XCTAssertEqual(ID3ChapterParser.parseChapters(from: Data()), [])
    }

    func testNonID3DataReturnsNoChapters() {
        XCTAssertEqual(ID3ChapterParser.parseChapters(from: Data("definitely not an mp3 file".utf8)), [])
        XCTAssertEqual(ID3ChapterParser.parseChapters(from: Data([0xFF, 0xFB, 0x90, 0x00, 0x12, 0x34])), [])
    }

    func testSingleChapterV23() {
        let chap = chapFrame(elementID: "chp0", startMs: 0, endMs: 30000,
                             subframes: textSubframe(text: [UInt8]("Intro".utf8), encoding: 0, version: .v2_3),
                             version: .v2_3)
        let chapters = ID3ChapterParser.parseChapters(from: tag(version: .v2_3, body: chap))

        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters.first?.elementID, "chp0")
        XCTAssertEqual(chapters.first?.title, "Intro")
        XCTAssertEqual(chapters.first?.startTimeMs, 0)
        XCTAssertEqual(chapters.first?.endTimeMs, 30000)
        XCTAssertEqual(chapters.first?.isHidden, false)
        XCTAssertNil(chapters.first?.artworkData)
        XCTAssertNil(chapters.first?.url)
    }

    func testV24SyncsafeFrameSizes() {
        // A payload longer than 127 bytes encodes differently as syncsafe vs plain big-endian,
        // so a correct round-trip proves the v2.4 syncsafe path is used for tag, frame and sub-frame.
        let longTitle = String(repeating: "a", count: 200)
        let chap = chapFrame(elementID: "c1", startMs: 1000, endMs: 2000,
                             subframes: textSubframe(text: [UInt8](longTitle.utf8), encoding: 3, version: .v2_4),
                             version: .v2_4)
        let chapters = ID3ChapterParser.parseChapters(from: tag(version: .v2_4, body: chap))

        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters.first?.title, longTitle)
        XCTAssertEqual(chapters.first?.startTimeMs, 1000)
        XCTAssertEqual(chapters.first?.endTimeMs, 2000)
    }

    // MARK: - CTOC handling

    func testCTOCOrderingWins() {
        // Chapters appear (and start) in one order; the table of contents lists them reversed.
        let body = chapFrame(elementID: "ch1", startMs: 0, endMs: 1000, version: .v2_3)
            + chapFrame(elementID: "ch2", startMs: 1000, endMs: 2000, version: .v2_3)
            + ctocFrame(childIDs: ["ch2", "ch1"], version: .v2_3)
        let chapters = ID3ChapterParser.parseChapters(from: tag(version: .v2_3, body: body))

        XCTAssertEqual(chapters.map(\.elementID), ["ch2", "ch1"])
        XCTAssertEqual(chapters.map(\.isHidden), [false, false])
    }

    func testChapterMissingFromCTOCIsHiddenAndAppendedLast() {
        let body = chapFrame(elementID: "ch1", startMs: 0, endMs: 1000, version: .v2_3)
            + chapFrame(elementID: "secret", startMs: 1000, endMs: 2000, version: .v2_3)
            + chapFrame(elementID: "ch2", startMs: 2000, endMs: 3000, version: .v2_3)
            + ctocFrame(childIDs: ["ch1", "ch2"], version: .v2_3)
        let chapters = ID3ChapterParser.parseChapters(from: tag(version: .v2_3, body: body))

        XCTAssertEqual(chapters.map(\.elementID), ["ch1", "ch2", "secret"])
        XCTAssertEqual(chapters.map(\.isHidden), [false, false, true])
    }

    func testAllChaptersHiddenWhenCTOCListsNone() {
        let body = chapFrame(elementID: "ch1", startMs: 0, endMs: 1000, version: .v2_3)
            + ctocFrame(childIDs: ["unrelated"], version: .v2_3)
        let chapters = ID3ChapterParser.parseChapters(from: tag(version: .v2_3, body: body))

        XCTAssertEqual(chapters.map(\.isHidden), [true])
    }

    func testMissingCTOCSortsByStartTime() {
        let body = chapFrame(elementID: "late", startMs: 60000, endMs: 90000, version: .v2_3)
            + chapFrame(elementID: "early", startMs: 0, endMs: 60000, version: .v2_3)
        let chapters = ID3ChapterParser.parseChapters(from: tag(version: .v2_3, body: body))

        XCTAssertEqual(chapters.map(\.elementID), ["early", "late"])
    }

    func testCTOCWithZeroEntryCountFallsBackToRemainingIDs() {
        // Broken writers leave the entry count at 0; the parser should still find the child IDs.
        var ctocPayload = [UInt8]("toc".utf8) + [0, 0x03, 0]
        ctocPayload += [UInt8]("ch1".utf8) + [0]
        let body = chapFrame(elementID: "ch1", startMs: 0, endMs: 1000, version: .v2_3)
            + chapFrame(elementID: "ch2", startMs: 1000, endMs: 2000, version: .v2_3)
            + frame(id: "CTOC", payload: ctocPayload, version: .v2_3)
        let chapters = ID3ChapterParser.parseChapters(from: tag(version: .v2_3, body: body))

        XCTAssertEqual(chapters.map(\.elementID), ["ch1", "ch2"])
        XCTAssertEqual(chapters.map(\.isHidden), [false, true])
    }

    // MARK: - Text encodings

    func testTitleEncodingLatin1() {
        XCTAssertEqual(parsedTitle(textBytes: [0x43, 0x61, 0x66, 0xE9], encoding: 0), "Café")
    }

    func testTitleEncodingUTF16WithBOMLittleEndian() {
        let bytes: [UInt8] = [0xFF, 0xFE, 0x43, 0x00, 0x61, 0x00, 0x66, 0x00, 0xE9, 0x00]
        XCTAssertEqual(parsedTitle(textBytes: bytes, encoding: 1), "Café")
    }

    func testTitleEncodingUTF16WithBOMBigEndian() {
        let bytes: [UInt8] = [0xFE, 0xFF, 0x00, 0x43, 0x00, 0x61, 0x00, 0x66, 0x00, 0xE9]
        XCTAssertEqual(parsedTitle(textBytes: bytes, encoding: 1), "Café")
    }

    func testTitleEncodingUTF16BigEndianNoBOM() {
        let bytes: [UInt8] = [0x00, 0x43, 0x00, 0x61, 0x00, 0x66, 0x00, 0xE9]
        XCTAssertEqual(parsedTitle(textBytes: bytes, encoding: 2), "Café")
    }

    func testTitleEncodingUTF8() {
        XCTAssertEqual(parsedTitle(textBytes: [UInt8]("Chapter 🎧".utf8), encoding: 3), "Chapter 🎧")
    }

    func testTitleTrailingNullTerminatorIsStripped() {
        XCTAssertEqual(parsedTitle(textBytes: [UInt8]("Intro".utf8) + [0], encoding: 0), "Intro")
        let utf16: [UInt8] = [0xFF, 0xFE, 0x48, 0x00, 0x69, 0x00, 0x00, 0x00]
        XCTAssertEqual(parsedTitle(textBytes: utf16, encoding: 1), "Hi")
    }

    // MARK: - APIC artwork

    func testAPICArtwork() {
        let imageBytes: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0x03]
        var apicPayload: [UInt8] = [0] // latin-1 encoding
        apicPayload += [UInt8]("image/jpeg".utf8) + [0]
        apicPayload += [0x03] // picture type: front cover
        apicPayload += [0] // empty description
        apicPayload += imageBytes

        let chap = chapFrame(elementID: "c1", startMs: 0, endMs: 1000,
                             subframes: frame(id: "APIC", payload: apicPayload, version: .v2_3),
                             version: .v2_3)
        let chapters = ID3ChapterParser.parseChapters(from: tag(version: .v2_3, body: chap))

        XCTAssertEqual(chapters.first?.artworkData, Data(imageBytes))
        XCTAssertEqual(chapters.first?.artworkMimeType, "image/jpeg")
    }

    func testAPICArtworkWithUTF16Description() {
        let imageBytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]
        var apicPayload: [UInt8] = [1] // UTF-16 with BOM
        apicPayload += [UInt8]("image/png".utf8) + [0]
        apicPayload += [0x03]
        apicPayload += [0xFF, 0xFE, 0x61, 0x00, 0x00, 0x00] // description "a" + double-null terminator
        apicPayload += imageBytes

        let chap = chapFrame(elementID: "c1", startMs: 0, endMs: 1000,
                             subframes: frame(id: "APIC", payload: apicPayload, version: .v2_3),
                             version: .v2_3)
        let chapters = ID3ChapterParser.parseChapters(from: tag(version: .v2_3, body: chap))

        XCTAssertEqual(chapters.first?.artworkData, Data(imageBytes))
        XCTAssertEqual(chapters.first?.artworkMimeType, "image/png")
    }

    // MARK: - WXXX links

    func testWXXXUrl() {
        var wxxxPayload: [UInt8] = [0] // latin-1 encoding
        wxxxPayload += [0] // empty description
        wxxxPayload += [UInt8]("https://example.com/page".utf8)

        let chap = chapFrame(elementID: "c1", startMs: 0, endMs: 1000,
                             subframes: frame(id: "WXXX", payload: wxxxPayload, version: .v2_3),
                             version: .v2_3)
        let chapters = ID3ChapterParser.parseChapters(from: tag(version: .v2_3, body: chap))

        XCTAssertEqual(chapters.first?.url, "https://example.com/page")
    }

    // MARK: - Malformed input

    func testTruncatedTagReturnsChaptersParsedBeforeTheDamage() {
        let body = chapFrame(elementID: "ch1", startMs: 0, endMs: 1000, version: .v2_3)
            + chapFrame(elementID: "ch2", startMs: 1000, endMs: 2000, version: .v2_3)
        let fullTag = tag(version: .v2_3, body: body)

        // Cut into the middle of the second CHAP frame while the header still declares the full size
        let truncated = fullTag.prefix(fullTag.count - 15)
        let chapters = ID3ChapterParser.parseChapters(from: truncated)

        XCTAssertEqual(chapters.map(\.elementID), ["ch1"])
    }

    func testTruncatedFrameReturnsNoChapters() {
        // A CHAP frame header that declares more content than the tag actually holds
        let payload = [UInt8]("c1".utf8) + [0] + be32(0) + be32(1000) + be32(0xFFFFFFFF) + be32(0xFFFFFFFF)
        let lyingFrame = [UInt8]("CHAP".utf8) + be32(UInt32(payload.count + 50)) + [0, 0] + payload
        let chapters = ID3ChapterParser.parseChapters(from: tag(version: .v2_3, body: lyingFrame))

        XCTAssertEqual(chapters, [])
    }

    func testZeroLengthFrameIsSkipped() {
        let body = frame(id: "TXXX", payload: [], version: .v2_3)
            + chapFrame(elementID: "ch1", startMs: 0, endMs: 1000, version: .v2_3)
        let chapters = ID3ChapterParser.parseChapters(from: tag(version: .v2_3, body: body))

        XCTAssertEqual(chapters.map(\.elementID), ["ch1"])
    }

    func testGarbageAfterTagIsIgnored() {
        let chap = chapFrame(elementID: "ch1", startMs: 0, endMs: 1000, version: .v2_3)
        var data = tag(version: .v2_3, body: chap)
        data.append(Data([0xFF, 0xFB, 0x90, 0x64, 0x00, 0x0F, 0xF0, 0xCC])) // MPEG audio frame sync + noise

        XCTAssertEqual(ID3ChapterParser.parseChapters(from: data).map(\.elementID), ["ch1"])
    }

    func testChapterPastDeclaredTagSizeIsIgnored() {
        // The declared body covers only the first CHAP; a second one after it belongs to the audio stream
        let first = chapFrame(elementID: "ch1", startMs: 0, endMs: 1000, version: .v2_3)
        let second = chapFrame(elementID: "ch2", startMs: 1000, endMs: 2000, version: .v2_3)
        var data = tag(version: .v2_3, body: first)
        data.append(Data(second))

        XCTAssertEqual(ID3ChapterParser.parseChapters(from: data).map(\.elementID), ["ch1"])
    }

    // MARK: - Extended headers

    func testExtendedHeaderV23IsSkipped() {
        // v2.3: 4-byte plain size that excludes the size field itself, followed by that many bytes
        let extendedHeader = be32(6) + [UInt8](repeating: 0, count: 6)
        let body = extendedHeader + chapFrame(elementID: "ch1", startMs: 0, endMs: 1000, version: .v2_3)
        let chapters = ID3ChapterParser.parseChapters(from: tag(version: .v2_3, flags: 0x40, body: body))

        XCTAssertEqual(chapters.map(\.elementID), ["ch1"])
    }

    func testExtendedHeaderV24IsSkipped() {
        // v2.4: syncsafe size that includes the whole extended header (minimum 6 bytes)
        let extendedHeader = syncsafe(6) + [0x01, 0x00] // number of flag bytes + flags
        let body = extendedHeader + chapFrame(elementID: "ch1", startMs: 0, endMs: 1000, version: .v2_4)
        let chapters = ID3ChapterParser.parseChapters(from: tag(version: .v2_4, flags: 0x40, body: body))

        XCTAssertEqual(chapters.map(\.elementID), ["ch1"])
    }

    // MARK: - Unsynchronisation

    func testTagLevelUnsynchronisationV23() {
        // startMs 0xFF00 and 0xFF bytes in the artwork force 0xFF bytes into the body,
        // which the writer then unsynchronises; the parser must reverse it tag-wide.
        let imageBytes: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0]
        var apicPayload: [UInt8] = [0]
        apicPayload += [UInt8]("image/jpeg".utf8) + [0]
        apicPayload += [0x03, 0]
        apicPayload += imageBytes
        let body = chapFrame(elementID: "ch1", startMs: 0xFF00, endMs: 0xFFFF,
                             subframes: frame(id: "APIC", payload: apicPayload, version: .v2_3),
                             version: .v2_3)

        let chapters = ID3ChapterParser.parseChapters(from: tag(version: .v2_3, flags: 0x80, body: unsynchronise(body)))

        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters.first?.startTimeMs, 0xFF00)
        XCTAssertEqual(chapters.first?.endTimeMs, 0xFFFF)
        XCTAssertEqual(chapters.first?.artworkData, Data(imageBytes))
    }

    func testPerFrameUnsynchronisationV24() {
        let payload = [UInt8]("ch1".utf8) + [0] + be32(0xFF00) + be32(0xFFFF) + be32(0xFFFFFFFF) + be32(0xFFFFFFFF)
        let unsyncedPayload = unsynchronise(payload)
        let chapFrameBytes = [UInt8]("CHAP".utf8) + syncsafe(unsyncedPayload.count) + [0, 0x02] + unsyncedPayload
        let chapters = ID3ChapterParser.parseChapters(from: tag(version: .v2_4, body: chapFrameBytes))

        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters.first?.elementID, "ch1")
        XCTAssertEqual(chapters.first?.startTimeMs, 0xFF00)
        XCTAssertEqual(chapters.first?.endTimeMs, 0xFFFF)
    }

    // MARK: - Tag length

    func testDeclaredTagLength() {
        let plain = Data([0x49, 0x44, 0x33, 4, 0, 0x00] + syncsafe(1000))
        XCTAssertEqual(ID3ChapterParser.declaredTagLength(fromHeader: plain), 1010)

        let withFooter = Data([0x49, 0x44, 0x33, 4, 0, 0x10] + syncsafe(1000))
        XCTAssertEqual(ID3ChapterParser.declaredTagLength(fromHeader: withFooter), 1020)

        // v2.3 has no footer, so the 0x10 bit must not add anything
        let v23 = Data([0x49, 0x44, 0x33, 3, 0, 0x10] + syncsafe(1000))
        XCTAssertEqual(ID3ChapterParser.declaredTagLength(fromHeader: v23), 1010)

        XCTAssertNil(ID3ChapterParser.declaredTagLength(fromHeader: Data("ID4x".utf8)))
        XCTAssertNil(ID3ChapterParser.declaredTagLength(fromHeader: Data([0x49, 0x44, 0x33])))
        XCTAssertNil(ID3ChapterParser.declaredTagLength(fromHeader: Data()))

        // A non-syncsafe size byte marks a corrupt header
        XCTAssertNil(ID3ChapterParser.declaredTagLength(fromHeader: Data([0x49, 0x44, 0x33, 4, 0, 0, 0x80, 0, 0, 0])))
    }

    // MARK: - Byte builders

    private enum Version {
        case v2_3, v2_4

        var majorByte: UInt8 { self == .v2_3 ? 3 : 4 }
    }

    /// Four 7-bit bytes, big-endian.
    private func syncsafe(_ value: Int) -> [UInt8] {
        [UInt8((value >> 21) & 0x7F), UInt8((value >> 14) & 0x7F), UInt8((value >> 7) & 0x7F), UInt8(value & 0x7F)]
    }

    private func be32(_ value: UInt32) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    /// Builds a complete frame: 4-byte ID, version-appropriate size, 2 flag bytes, payload.
    private func frame(id: String, payload: [UInt8], version: Version, formatFlags: UInt8 = 0) -> [UInt8] {
        let sizeBytes = version == .v2_4 ? syncsafe(payload.count) : be32(UInt32(payload.count))
        return [UInt8](id.utf8) + sizeBytes + [0, formatFlags] + payload
    }

    private func textSubframe(id: String = "TIT2", text: [UInt8], encoding: UInt8, version: Version) -> [UInt8] {
        frame(id: id, payload: [encoding] + text, version: version)
    }

    /// CHAP: element ID (null-terminated), start/end ms, start/end byte offsets (0xFFFFFFFF = unused),
    /// then optional embedded sub-frames.
    private func chapFrame(elementID: String, startMs: UInt32, endMs: UInt32, subframes: [UInt8] = [], version: Version) -> [UInt8] {
        let payload = [UInt8](elementID.utf8) + [0]
            + be32(startMs) + be32(endMs) + be32(0xFFFFFFFF) + be32(0xFFFFFFFF)
            + subframes
        return frame(id: "CHAP", payload: payload, version: version)
    }

    /// CTOC: element ID (null-terminated), flags (0x03 = top-level + ordered), entry count,
    /// then the null-terminated child element IDs.
    private func ctocFrame(childIDs: [String], flags: UInt8 = 0x03, version: Version) -> [UInt8] {
        var payload = [UInt8]("toc".utf8) + [0, flags, UInt8(childIDs.count)]
        for childID in childIDs {
            payload += [UInt8](childID.utf8) + [0]
        }
        return frame(id: "CTOC", payload: payload, version: version)
    }

    /// Full tag: "ID3", version, flags, syncsafe body size, body. Pass `declaredBodyLength`
    /// to lie about the size (for truncation tests).
    private func tag(version: Version, flags: UInt8 = 0, body: [UInt8], declaredBodyLength: Int? = nil) -> Data {
        Data([0x49, 0x44, 0x33, version.majorByte, 0, flags] + syncsafe(declaredBodyLength ?? body.count) + body)
    }

    /// Writer-side unsynchronisation: inserts 0x00 after every 0xFF.
    private func unsynchronise(_ bytes: [UInt8]) -> [UInt8] {
        var result = [UInt8]()
        result.reserveCapacity(bytes.count)
        for byte in bytes {
            result.append(byte)
            if byte == 0xFF {
                result.append(0)
            }
        }
        return result
    }

    private func parsedTitle(textBytes: [UInt8], encoding: UInt8, version: Version = .v2_3) -> String? {
        let chap = chapFrame(elementID: "c1", startMs: 0, endMs: 1000,
                             subframes: textSubframe(text: textBytes, encoding: encoding, version: version),
                             version: version)
        return ID3ChapterParser.parseChapters(from: tag(version: version, body: chap)).first?.title
    }
}
