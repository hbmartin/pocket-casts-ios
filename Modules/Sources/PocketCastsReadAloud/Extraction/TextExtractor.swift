import Foundation
import NaturalLanguage
import UniformTypeIdentifiers

public extension UTType {
    /// Markdown's de-facto identifier. Declared here rather than relying on the
    /// system: `UTType(filenameExtension: "md")` resolves to a dynamic type on
    /// machines where no installed app has declared Markdown, and a dynamic type
    /// conforms to nothing useful.
    static let readAloudMarkdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

/// Turns a text file's bytes into narratable blocks. One conformer per document
/// format; adding PDF or HTML later means adding a conformer and registering it,
/// with nothing else in the pipeline changing.
public protocol TextExtractor: Sendable {
    /// Types this extractor claims. Matching is by conformance, so a subtype of
    /// a listed type routes here too.
    var supportedTypes: [UTType] { get }
    /// Lowercased filename extensions this extractor claims, used when the
    /// caller has no `UTType` or the system resolved a dynamic one.
    var supportedFilenameExtensions: Set<String> { get }

    func extract(data: Data, filename: String?) throws -> ExtractedDocument
}

/// Resolves the extractor for a document and runs it.
///
/// Resolution tries filename extension before `UTType`, which is backwards from
/// how the rest of the app routes files but correct here: Markdown's UTType is
/// only as good as the declarations on the running machine, whereas `.md` is
/// unambiguous. A `.md` file whose type resolved to bare `public.plain-text`
/// must still get Markdown treatment, or its `#` headings are read aloud as
/// "number sign".
public struct TextExtractorRegistry: Sendable {
    public static let standard = TextExtractorRegistry(extractors: [MarkdownExtractor(), PlainTextExtractor()])

    private let extractors: [any TextExtractor]

    public init(extractors: [any TextExtractor]) {
        self.extractors = extractors
    }

    /// Every type any registered extractor claims — what the document picker's
    /// allowed-types list is built from.
    public var supportedTypes: [UTType] {
        extractors.flatMap(\.supportedTypes)
    }

    public func extractor(filename: String?, type: UTType?) -> (any TextExtractor)? {
        if let ext = filename.map({ ($0 as NSString).pathExtension.lowercased() }), !ext.isEmpty,
           let match = extractors.first(where: { $0.supportedFilenameExtensions.contains(ext) }) {
            return match
        }
        if let type {
            return extractors.first { extractor in
                extractor.supportedTypes.contains { type.conforms(to: $0) }
            }
        }
        return nil
    }

    public func extract(data: Data, filename: String?, type: UTType?) throws -> ExtractedDocument {
        guard let extractor = extractor(filename: filename, type: type) else {
            throw ReadAloudError.unsupportedFileType
        }
        return try extractor.extract(data: data, filename: filename)
    }
}

// MARK: - Shared assembly

/// The tail end every extractor shares: drop empties, count characters, detect
/// language, choose a title. Kept here so two extractors can't disagree about
/// what `characterCount` counts.
enum ExtractedDocumentBuilder {
    /// Documents above this are refused. ~500k characters is roughly ten hours
    /// of narration — past the point where eager whole-document synthesis is a
    /// sensible thing to start.
    static let characterLimit = 500_000

    static func build(blocks: [DocumentBlock], filename: String?) throws -> ExtractedDocument {
        let usable = blocks.filter { !$0.text.isEmpty }
        guard !usable.isEmpty else { throw ReadAloudError.emptyDocument }

        // Counts narratable text only — not markup, not the file's byte size —
        // because this is what the user is charged for and what the duration
        // estimate is derived from.
        let characterCount = usable.reduce(0) { $0 + $1.text.count }
        guard characterCount <= characterLimit else {
            throw ReadAloudError.documentTooLarge(limit: characterLimit)
        }

        return ExtractedDocument(
            suggestedTitle: title(from: usable, filename: filename),
            blocks: usable,
            characterCount: characterCount,
            detectedLanguage: detectLanguage(in: usable)
        )
    }

    /// A leading heading is the author's own title and beats the filename; the
    /// filename beats a truncated first sentence, which is the last resort for
    /// pasted text with no heading.
    private static func title(from blocks: [DocumentBlock], filename: String?) -> String {
        if let first = blocks.first, case .heading = first.kind {
            return first.text
        }
        if let filename, case let stem = (filename as NSString).deletingPathExtension, !stem.isEmpty {
            return stem
        }
        guard let opening = blocks.first?.text else { return "" }
        return opening.count <= 60 ? opening : String(opening.prefix(60)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Detection runs over a prefix rather than the whole document: a few
    /// thousand characters is plenty for `NLLanguageRecognizer`, and long
    /// documents shouldn't pay for a full pass at import time.
    private static func detectLanguage(in blocks: [DocumentBlock]) -> String? {
        let sample = String(blocks.map(\.text).joined(separator: "\n").prefix(4000))
        guard sample.count >= 20 else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let language = recognizer.dominantLanguage, language != .undetermined else { return nil }

        // A confident-looking guess from a short or mixed sample is worse than
        // none: it silently preselects the wrong voice.
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        guard let confidence = hypotheses[language], confidence >= 0.5 else { return nil }
        return language.rawValue
    }

    /// Collapses runs of whitespace (including the newlines inside a wrapped
    /// paragraph) to single spaces and trims. Synthesizers pause on line breaks,
    /// so a hard-wrapped paragraph read verbatim sounds stilted.
    static func normalize(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
