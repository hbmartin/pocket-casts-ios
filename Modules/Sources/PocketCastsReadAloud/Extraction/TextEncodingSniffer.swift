import Foundation

/// Decodes a text file's bytes to a `String` without asking the user what
/// encoding they used.
///
/// The ladder is BOM → UTF-8 → platform sniff → Windows-1252, in that order and
/// for a reason: a BOM is a declaration and outranks guessing; UTF-8 is what
/// virtually every modern `.txt`/`.md` actually is, and a strict UTF-8 decode
/// that succeeds is almost never a false positive; only then is it worth letting
/// `NSString` guess. Windows-1252 is the terminal fallback because every one of
/// its 256 byte values maps to a character, so it cannot fail — a mojibake
/// narration beats refusing to read the file at all.
public enum TextEncodingSniffer: Sendable {
    public struct Decoded: Sendable, Equatable {
        public let text: String
        public let encoding: String.Encoding
        /// True when the text came from the terminal fallback rather than a BOM,
        /// a clean UTF-8 decode or a platform guess. Callers may surface this as
        /// a "characters may look wrong" hint.
        public let usedFallback: Bool
    }

    /// Encodings offered to the platform sniffer, most likely first.
    private static let sniffCandidates: [String.Encoding] = [
        .utf8, .isoLatin1, .windowsCP1252, .macOSRoman, .isoLatin2,
    ]

    public static func decode(_ data: Data) -> Decoded? {
        guard !data.isEmpty else { return nil }

        if let bomDecoded = decodeUsingBOM(data) {
            return bomDecoded
        }

        if let utf8 = String(data: data, encoding: .utf8) {
            return Decoded(text: utf8, encoding: .utf8, usedFallback: false)
        }

        if let sniffed = platformSniff(data) {
            return sniffed
        }

        // Windows-1252 has no unmapped byte values, so this cannot return nil —
        // the optional chain is defensive only.
        guard let fallback = String(data: data, encoding: .windowsCP1252) else { return nil }
        return Decoded(text: fallback, encoding: .windowsCP1252, usedFallback: true)
    }

    // MARK: - Ladder steps

    /// Honors a leading byte-order mark and strips it from the result. UTF-32
    /// must be tested before UTF-16: a little-endian UTF-32 BOM starts with the
    /// same two bytes as a little-endian UTF-16 one.
    private static func decodeUsingBOM(_ data: Data) -> Decoded? {
        let marks: [(bytes: [UInt8], encoding: String.Encoding)] = [
            ([0x00, 0x00, 0xFE, 0xFF], .utf32BigEndian),
            ([0xFF, 0xFE, 0x00, 0x00], .utf32LittleEndian),
            ([0xEF, 0xBB, 0xBF], .utf8),
            ([0xFE, 0xFF], .utf16BigEndian),
            ([0xFF, 0xFE], .utf16LittleEndian),
        ]

        for mark in marks where data.starts(with: mark.bytes) {
            let body = data.dropFirst(mark.bytes.count)
            guard let text = String(data: body, encoding: mark.encoding) else { continue }
            return Decoded(text: text, encoding: mark.encoding, usedFallback: false)
        }
        return nil
    }

    /// `NSString`'s statistical guess, constrained to the candidate list. It
    /// reports lossy conversions, which we reject: a lossy guess is no better
    /// than the deterministic Windows-1252 fallback and pretends to more
    /// confidence.
    private static func platformSniff(_ data: Data) -> Decoded? {
        var converted: NSString?
        var lossy: ObjCBool = false
        let raw = NSString.stringEncoding(
            for: data,
            encodingOptions: [
                .suggestedEncodingsKey: sniffCandidates.map(\.rawValue),
                .useOnlySuggestedEncodingsKey: true,
                .allowLossyKey: false,
            ],
            convertedString: &converted,
            usedLossyConversion: &lossy
        )

        guard raw != 0, !lossy.boolValue, let converted else { return nil }
        return Decoded(text: converted as String, encoding: String.Encoding(rawValue: raw), usedFallback: false)
    }
}
