import Foundation
import UniformTypeIdentifiers

/// `.txt` and anything else that is plain prose: blank lines separate
/// paragraphs, and nothing in the text is markup.
public struct PlainTextExtractor: TextExtractor {
    public let supportedTypes: [UTType] = [.plainText, .utf8PlainText, .text]
    public let supportedFilenameExtensions: Set<String> = ["txt", "text"]

    public init() {}

    public func extract(data: Data, filename: String?) throws -> ExtractedDocument {
        guard let decoded = TextEncodingSniffer.decode(data) else {
            throw ReadAloudError.undecodableText
        }
        let blocks = Self.paragraphs(in: decoded.text).map {
            DocumentBlock(kind: .paragraph, text: $0)
        }
        return try ExtractedDocumentBuilder.build(blocks: blocks, filename: filename)
    }

    /// Splits on blank lines. A file with no blank line at all is one long
    /// paragraph, which is correct — the chunker, not the extractor, is what
    /// keeps that from becoming one enormous synthesis request.
    static func paragraphs(in text: String) -> [String] {
        var paragraphs: [String] = []
        var current: [Substring] = []

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.allSatisfy(\.isWhitespace) {
                if !current.isEmpty {
                    paragraphs.append(ExtractedDocumentBuilder.normalize(current.joined(separator: " ")))
                    current.removeAll()
                }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty {
            paragraphs.append(ExtractedDocumentBuilder.normalize(current.joined(separator: " ")))
        }
        return paragraphs.filter { !$0.isEmpty }
    }
}
