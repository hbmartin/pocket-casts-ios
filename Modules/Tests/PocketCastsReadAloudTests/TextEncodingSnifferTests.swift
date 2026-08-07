import Foundation
import Testing
@testable import PocketCastsReadAloud

@Suite("Text encoding sniffing")
struct TextEncodingSnifferTests {
    @Test("Plain UTF-8 decodes without the fallback")
    func plainUTF8() throws {
        let decoded = try #require(TextEncodingSniffer.decode(Data("Café — naïve".utf8)))
        #expect(decoded.text == "Café — naïve")
        #expect(decoded.encoding == .utf8)
        #expect(decoded.usedFallback == false)
    }

    @Test("A UTF-8 BOM is honoured and stripped from the text")
    func utf8BOM() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("Hello".utf8))

        let decoded = try #require(TextEncodingSniffer.decode(data))
        #expect(decoded.text == "Hello")
        #expect(decoded.encoding == .utf8)
        #expect(decoded.usedFallback == false)
    }

    @Test("UTF-16 BOMs decode in both byte orders")
    func utf16BOMs() throws {
        let little = try #require(TextEncodingSniffer.decode(Data([0xFF, 0xFE, 0x48, 0x00, 0x69, 0x00])))
        #expect(little.text == "Hi")
        #expect(little.encoding == .utf16LittleEndian)

        let big = try #require(TextEncodingSniffer.decode(Data([0xFE, 0xFF, 0x00, 0x48, 0x00, 0x69])))
        #expect(big.text == "Hi")
        #expect(big.encoding == .utf16BigEndian)
    }

    /// A little-endian UTF-32 BOM opens with the same two bytes as a
    /// little-endian UTF-16 one, so order in the BOM table is load-bearing.
    @Test("A UTF-32 BOM is not mistaken for UTF-16")
    func utf32NotConfusedWithUTF16() throws {
        let data = Data([0xFF, 0xFE, 0x00, 0x00, 0x48, 0x00, 0x00, 0x00])

        let decoded = try #require(TextEncodingSniffer.decode(data))
        #expect(decoded.text == "H")
        #expect(decoded.encoding == .utf32LittleEndian)
    }

    @Test("Legacy single-byte bytes still decode to something readable")
    func legacyBytesDecode() throws {
        // 0xE9 is "é" in Latin-1/CP1252 and invalid as standalone UTF-8.
        let data = Data([0x43, 0x61, 0x66, 0xE9])

        let decoded = try #require(TextEncodingSniffer.decode(data))
        #expect(decoded.text == "Café")
        #expect(decoded.encoding != .utf8)
    }

    /// CP1252 assigns 0x93/0x94 to curly quotes where Latin-1 leaves them as
    /// control characters — the case that most often lands in a pasted `.txt`.
    @Test("Windows-1252 punctuation survives")
    func windows1252Punctuation() throws {
        let data = Data([0x93, 0x48, 0x69, 0x94])

        let decoded = try #require(TextEncodingSniffer.decode(data))
        #expect(decoded.text.contains("Hi"))
        #expect(decoded.text.contains("\u{FFFD}") == false)
    }

    @Test("Empty input has nothing to decode")
    func emptyInput() {
        #expect(TextEncodingSniffer.decode(Data()) == nil)
    }
}
