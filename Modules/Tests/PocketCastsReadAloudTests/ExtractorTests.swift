import Foundation
import Testing
import UniformTypeIdentifiers
@testable import PocketCastsReadAloud

private func extractMarkdown(_ source: String, filename: String? = "doc.md") throws -> ExtractedDocument {
    try MarkdownExtractor().extract(data: Data(source.utf8), filename: filename)
}

private func extractPlain(_ source: String, filename: String? = "doc.txt") throws -> ExtractedDocument {
    try PlainTextExtractor().extract(data: Data(source.utf8), filename: filename)
}

private extension DocumentBlock {
    var headingLevel: Int? {
        if case .heading(let level) = kind { return level }
        return nil
    }
}

@Suite("Plain text extraction")
struct PlainTextExtractorTests {
    @Test("Blank lines separate paragraphs")
    func paragraphSplitting() throws {
        let document = try extractPlain("First para.\n\nSecond para.\n\n\nThird para.")

        #expect(document.blocks.count == 3)
        #expect(document.blocks.map(\.text) == ["First para.", "Second para.", "Third para."])
        #expect(document.blocks.allSatisfy { $0.headingLevel == nil })
    }

    /// Hard-wrapped prose is one paragraph — a synthesizer pauses at every line
    /// break, so preserving them makes the narration stutter.
    @Test("Hard-wrapped lines join into one paragraph")
    func hardWrapsCollapse() throws {
        let document = try extractPlain("The quick brown\nfox jumps over\nthe lazy dog.")

        #expect(document.blocks.count == 1)
        #expect(document.blocks[0].text == "The quick brown fox jumps over the lazy dog.")
    }

    @Test("Whitespace-only lines count as blank")
    func whitespaceOnlyLinesSeparate() throws {
        let document = try extractPlain("One.\n   \t \nTwo.")

        #expect(document.blocks.map(\.text) == ["One.", "Two."])
    }

    @Test("Title falls back to the filename stem")
    func titleFromFilename() throws {
        let document = try extractPlain("Body text here.", filename: "My Notes.txt")

        #expect(document.suggestedTitle == "My Notes")
    }

    @Test("Untitled pasted text is titled from its opening")
    func titleFromOpeningLine() throws {
        let document = try extractPlain("A short opening line.", filename: nil)

        #expect(document.suggestedTitle == "A short opening line.")
    }

    @Test("Character count covers narratable text only")
    func characterCount() throws {
        let document = try extractPlain("abc\n\ndef")

        #expect(document.characterCount == 6)
    }

    @Test("Lightweight count matches normalized extraction")
    func narratableCharacterCountMatchesExtraction() throws {
        let text = "  First   wrapped\nline.  \n\n  Second paragraph.  "
        let extractor = PlainTextExtractor()
        let document = try extractor.extract(data: Data(text.utf8), filename: nil)

        #expect(extractor.narratableCharacterCount(in: text) == document.characterCount)
        #expect(extractor.narratableCharacterCount(in: " \n\t\n ") == 0)
    }

    @Test("A document with no narratable text is refused")
    func emptyDocumentThrows() {
        #expect(throws: ReadAloudError.emptyDocument) {
            try extractPlain("   \n\n  \n")
        }
    }

    @Test("Oversized documents are refused before any synthesis")
    func oversizedDocumentThrows() {
        let huge = String(repeating: "a", count: ExtractedDocumentBuilder.characterLimit + 1)

        #expect(throws: ReadAloudError.documentTooLarge(limit: ExtractedDocumentBuilder.characterLimit)) {
            try extractPlain(huge)
        }
    }
}

@Suite("Markdown extraction")
struct MarkdownExtractorTests {
    @Test("ATX headings become heading blocks at their level")
    func atxHeadings() throws {
        let document = try extractMarkdown("# Title\n\nBody.\n\n### Deep\n\nMore.")

        #expect(document.blocks[0].headingLevel == 1)
        #expect(document.blocks[0].text == "Title")
        #expect(document.blocks[1].headingLevel == nil)
        #expect(document.blocks[2].headingLevel == 3)
        #expect(document.blocks[2].text == "Deep")
    }

    /// CommonMark: a closing sequence must be preceded by whitespace, so "## #"
    /// is an *empty* heading. Regressed once by trimming before matching, which
    /// removed the whitespace the pattern needed and left a heading reading "#".
    @Test("A lone closing hash yields an empty heading, not a heading of '#'")
    func loneClosingHashIsNotContent() throws {
        let document = try extractMarkdown("## #\n\nBody text.")

        #expect(document.blocks.map(\.text) == ["Body text."])
    }

    @Test("Multiple closing hashes with nothing else yield an empty heading")
    func onlyClosingHashes() throws {
        let document = try extractMarkdown("## ###\n\nBody text.")

        #expect(document.blocks.map(\.text) == ["Body text."])
    }

    @Test("Closing hashes are decoration, not content")
    func atxClosingHashes() throws {
        let document = try extractMarkdown("## Title ##\n\nBody.")

        #expect(document.blocks[0].text == "Title")
    }

    /// The hash in "C#" is content: only a whitespace-preceded run of hashes is
    /// a closing decoration.
    @Test("A trailing hash that is part of a word survives")
    func trailingHashInsideWordSurvives() throws {
        let document = try extractMarkdown("## Learning C#\n\nBody.")

        #expect(document.blocks[0].text == "Learning C#")
    }

    /// "#hashtag" has no space after the hashes, so it is prose.
    @Test("A hash without a space is not a heading")
    func hashWithoutSpaceIsProse() throws {
        let document = try extractMarkdown("#nothashtag is just text.")

        #expect(document.blocks[0].headingLevel == nil)
        #expect(document.blocks[0].text == "#nothashtag is just text.")
    }

    @Test("Setext underlines promote the preceding line")
    func setextHeadings() throws {
        let document = try extractMarkdown("Title\n=====\n\nBody.\n\nSub\n---\n\nMore.")

        #expect(document.blocks[0].headingLevel == 1)
        #expect(document.blocks[0].text == "Title")
        #expect(document.blocks[2].headingLevel == 2)
        #expect(document.blocks[2].text == "Sub")
    }

    @Test("Fenced code blocks are dropped entirely")
    func fencedCodeDropped() throws {
        let document = try extractMarkdown("""
        Before.

        ```swift
        let x = 1
        # not a heading
        ```

        After.
        """)

        #expect(document.blocks.map(\.text) == ["Before.", "After."])
    }

    @Test("Tilde fences are dropped too")
    func tildeFencesDropped() throws {
        let document = try extractMarkdown("Before.\n\n~~~\nraw stuff\n~~~\n\nAfter.")

        #expect(document.blocks.map(\.text) == ["Before.", "After."])
    }

    /// A fence needs three markers; a shorter run must not swallow the rest of
    /// the document as an unterminated code block.
    @Test("Fewer than three backticks do not open a fence")
    func shortBacktickRunIsNotAFence() throws {
        let document = try extractMarkdown("`\n\nStill prose.")

        #expect(document.blocks.map(\.text).contains("Still prose."))
    }

    @Test("Links keep their text and lose their target")
    func linksKeepText() throws {
        let document = try extractMarkdown("See [the docs](https://example.com/a/b) for more.")

        #expect(document.blocks[0].text == "See the docs for more.")
    }

    @Test("Images are dropped rather than narrated")
    func imagesDropped() throws {
        let document = try extractMarkdown("Look: ![a diagram](img.png) done.")

        #expect(document.blocks[0].text == "Look: done.")
    }

    @Test("Emphasis markers are stripped")
    func emphasisStripped() throws {
        let document = try extractMarkdown("This is **bold**, *italic*, `code` and ~~struck~~.")

        #expect(document.blocks[0].text == "This is bold, italic, code and struck.")
    }

    /// Underscores inside identifiers are not emphasis — stripping them would
    /// turn "some_var_name" into "somevarname".
    @Test("snake_case survives the emphasis pass")
    func snakeCaseSurvives() throws {
        let document = try extractMarkdown("Call some_var_name twice.")

        #expect(document.blocks[0].text == "Call some_var_name twice.")
    }

    @Test("Each list item is its own block")
    func listItemsBecomeBlocks() throws {
        let document = try extractMarkdown("- alpha\n- beta\n\n1. one\n2. two")

        #expect(document.blocks.map(\.text) == ["alpha", "beta", "one", "two"])
    }

    @Test("Blockquote markers are stripped")
    func blockquotesStripped() throws {
        let document = try extractMarkdown("> quoted wisdom\n> continued here")

        #expect(document.blocks.map(\.text) == ["quoted wisdom continued here"])
    }

    @Test("Table rows read as comma-separated cells, separators dropped")
    func tablesFlatten() throws {
        let document = try extractMarkdown("| Name | Age |\n| --- | :-: |\n| Ada | 36 |")

        #expect(document.blocks.map(\.text) == ["Name, Age", "Ada, 36"])
    }

    @Test("YAML front matter is metadata, not prose")
    func frontMatterDropped() throws {
        let document = try extractMarkdown("---\ntitle: Hidden\ndraft: true\n---\n\n# Real Title\n\nBody.")

        #expect(document.blocks[0].headingLevel == 1)
        #expect(document.blocks[0].text == "Real Title")
        #expect(document.blocks.contains { $0.text.contains("draft") } == false)
    }

    @Test("Thematic breaks and reference definitions say nothing")
    func breaksAndRefsDropped() throws {
        let document = try extractMarkdown("One.\n\n***\n\n[ref]: https://example.com\n\nTwo.")

        #expect(document.blocks.map(\.text) == ["One.", "Two."])
    }

    @Test("Stray HTML tags are stripped")
    func htmlStripped() throws {
        let document = try extractMarkdown("A <em>tagged</em> line.<br/>")

        #expect(document.blocks[0].text == "A tagged line.")
    }

    @Test("A leading heading supplies the title")
    func titleFromLeadingHeading() throws {
        let document = try extractMarkdown("# The Real Title\n\nBody.", filename: "whatever.md")

        #expect(document.suggestedTitle == "The Real Title")
    }
}

@Suite("Extractor registry")
struct TextExtractorRegistryTests {
    private let registry = TextExtractorRegistry.standard

    @Test("Markdown files route to the Markdown extractor")
    func markdownByExtension() throws {
        let extractor = try #require(registry.extractor(filename: "notes.md", type: .plainText))

        #expect(extractor is MarkdownExtractor)
    }

    /// Markdown's UTType resolves to a dynamic type on machines where nothing
    /// declares it, so the extension has to win.
    @Test("A .md file typed as plain text still gets Markdown treatment")
    func markdownWinsOverPlainTextType() throws {
        let document = try registry.extract(data: Data("# Heading\n\nBody.".utf8), filename: "notes.md", type: .plainText)

        #expect(document.blocks[0].text == "Heading")
        #expect(document.blocks[0].headingLevel == 1)
    }

    @Test("Text files route to the plain-text extractor")
    func plainTextByExtension() throws {
        let extractor = try #require(registry.extractor(filename: "notes.txt", type: nil))

        #expect(extractor is PlainTextExtractor)
    }

    @Test("Type conformance resolves files with no usable filename")
    func typeConformanceFallback() throws {
        let extractor = try #require(registry.extractor(filename: nil, type: .utf8PlainText))

        #expect(extractor is PlainTextExtractor)
    }

    @Test("Unclaimed documents are refused")
    func unsupportedType() {
        #expect(registry.extractor(filename: "clip.mp3", type: .mp3) == nil)
        #expect(throws: ReadAloudError.unsupportedFileType) {
            try registry.extract(data: Data("x".utf8), filename: "clip.mp3", type: .mp3)
        }
    }

    @Test("Structured text formats do not fall through to plain text")
    func structuredTextRequiresADedicatedExtractor() {
        #expect(registry.extractor(filename: nil, type: .rtf) == nil)
        #expect(registry.extractor(filename: nil, type: .html) == nil)
    }
}
