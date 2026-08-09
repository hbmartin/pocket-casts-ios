import Foundation
import Testing
@testable import PocketCastsReadAloud

private func document(_ blocks: [DocumentBlock]) -> ExtractedDocument {
    ExtractedDocument(
        suggestedTitle: "Doc",
        blocks: blocks,
        characterCount: blocks.reduce(0) { $0 + $1.text.count },
        detectedLanguage: nil
    )
}

private func paragraphs(_ texts: String...) -> ExtractedDocument {
    document(texts.map { DocumentBlock(kind: .paragraph, text: $0) })
}

@Suite("Text chunking")
struct TextChunkerTests {
    private let chunker = TextChunker()

    @Test("Short documents produce a single chunk")
    func singleChunk() {
        let chunks = chunker.chunks(for: paragraphs("One sentence here."), maxCharacters: 2500)

        #expect(chunks.count == 1)
        #expect(chunks[0].text == "One sentence here.")
        #expect(chunks[0].index == 0)
        #expect(chunks[0].startsBlock)
    }

    @Test("Indices are contiguous from zero")
    func contiguousIndices() {
        let long = Array(repeating: "This is a sentence of some length.", count: 60).joined(separator: " ")
        let chunks = chunker.chunks(for: paragraphs(long), maxCharacters: 300)

        #expect(chunks.count > 1)
        #expect(chunks.map(\.index) == Array(0..<chunks.count))
    }

    /// Rule 2: a chunk may never span a paragraph, because paragraph edges are
    /// where the assembler inserts pauses.
    @Test("A chunk never spans two blocks")
    func blocksNeverMerge() {
        let chunks = chunker.chunks(for: paragraphs("Alpha.", "Beta.", "Gamma."), maxCharacters: 2500)

        #expect(chunks.map(\.text) == ["Alpha.", "Beta.", "Gamma."])
        #expect(chunks.allSatisfy { $0.startsBlock })
    }

    @Test("Only the first chunk of a split block starts a block")
    func startsBlockOnlyAtBlockOpening() {
        let long = Array(repeating: "Sentence number one.", count: 40).joined(separator: " ")
        let chunks = chunker.chunks(for: paragraphs(long), maxCharacters: 300)

        #expect(chunks.count > 1)
        #expect(chunks[0].startsBlock)
        #expect(chunks.dropFirst().allSatisfy { !$0.startsBlock })
    }

    @Test("Headings are their own chunk")
    func headingsChunkAlone() {
        let doc = document([
            DocumentBlock(kind: .heading(level: 1), text: "The Title"),
            DocumentBlock(kind: .paragraph, text: "Body text follows."),
        ])
        let chunks = chunker.chunks(for: doc, maxCharacters: 2500)

        #expect(chunks.map(\.text) == ["The Title", "Body text follows."])
    }

    /// Rule 1, the one that matters most: a sentence cut in half is audibly
    /// wrong at the seam.
    @Test("Sentences are never split when they fit")
    func sentencesStayWhole() {
        let sentences = (1...20).map { "This is sentence number \($0) in the document." }
        let chunks = chunker.chunks(for: paragraphs(sentences.joined(separator: " ")), maxCharacters: 200)

        #expect(chunks.count > 1)
        for sentence in sentences {
            #expect(chunks.contains { $0.text.contains(sentence) }, "sentence was split: \(sentence)")
        }
    }

    /// The minimum-target floor exists to avoid single-word chunks, but the
    /// stated limit is a hard cap the floor must never push a chunk past.
    @Test("A limit below the minimum target still caps every chunk")
    func tinyLimitNeverExceeded() {
        let sentences = (1...10).map { "Sentence number \($0) sits here." }
        let chunks = chunker.chunks(for: paragraphs(sentences.joined(separator: " ")), maxCharacters: 100)

        #expect(!chunks.isEmpty)
        #expect(chunks.allSatisfy { $0.text.count <= 100 })
    }

    @Test("Chunks respect the fill target, not just the hard limit")
    func chunksStayUnderTarget() {
        let long = Array(repeating: "A modest sentence.", count: 100).joined(separator: " ")
        let maxCharacters = 500
        let target = Int(Double(maxCharacters) * TextChunker.fillRatio)

        let chunks = chunker.chunks(for: paragraphs(long), maxCharacters: maxCharacters)

        #expect(chunks.allSatisfy { $0.text.count <= target })
    }

    @Test("No chunk is empty or whitespace-only")
    func noEmptyChunks() {
        let chunks = chunker.chunks(for: paragraphs("One.  ", "  ", "Two."), maxCharacters: 2500)

        #expect(chunks.allSatisfy { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    @Test("An empty document produces no chunks")
    func emptyDocument() {
        #expect(chunker.chunks(for: document([]), maxCharacters: 2500).isEmpty)
    }

    // MARK: - Pathological input

    /// One sentence longer than the target has to break rule 1. It should break
    /// at word boundaries, and every character must survive.
    @Test("An oversized sentence hard-splits without losing text")
    func oversizedSentenceSplits() {
        let sentence = Array(repeating: "word", count: 400).joined(separator: " ")
        let chunks = chunker.chunks(for: paragraphs(sentence), maxCharacters: 300)

        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.text.count <= Int(300 * TextChunker.fillRatio) })
        let rejoined = chunks.map(\.text).joined(separator: " ")
        #expect(rejoined == sentence)
    }

    @Test("Splitting an oversized sentence preserves punctuation")
    func oversizedSentencePreservesPunctuation() {
        let sentence = Array(
            repeating: "Wait, really? Parentheses (and semicolons; too) must survive!",
            count: 20
        ).joined(separator: " ")
        let target = 120

        let pieces = TextChunker.fitting(sentence, within: target)

        #expect(pieces.count > 1)
        #expect(pieces.allSatisfy { $0.count <= target })
        #expect(pieces.joined(separator: " ") == sentence)
    }

    /// A "word" with no break opportunity at all — a URL, a base64 blob — must
    /// still be cut rather than exceeding the limit.
    @Test("A single unbreakable token is cut by character")
    func unbreakableTokenIsCut() {
        let token = String(repeating: "x", count: 900)
        let target = Int(300 * TextChunker.fillRatio)

        let chunks = chunker.chunks(for: paragraphs(token), maxCharacters: 300)

        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.text.count <= target })
        #expect(chunks.map(\.text).joined() == token)
    }

    @Test("A tiny stated limit still yields workable chunks")
    func tinyLimitClampsToFloor() {
        let long = Array(repeating: "Short one.", count: 50).joined(separator: " ")

        let chunks = chunker.chunks(for: paragraphs(long), maxCharacters: 10)

        #expect(chunks.allSatisfy { $0.text.count <= TextChunker.minimumTarget })
        #expect(chunks.allSatisfy { !$0.text.isEmpty })
    }

    // MARK: - Non-Latin scripts

    /// CJK has no spaces and its own sentence terminator, which is exactly why
    /// the chunker uses `NLTokenizer` instead of splitting on punctuation.
    @Test("Japanese text splits on its own sentence terminators")
    func japaneseSentenceSplitting() {
        let sentences = Array(repeating: "これはテストの文章です。", count: 40).joined()
        let chunks = chunker.chunks(for: paragraphs(sentences), maxCharacters: 200)

        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { !$0.text.isEmpty })
        // Sentence integrity: no chunk may end mid-sentence when whole sentences
        // were available to pack.
        #expect(chunks.dropLast().allSatisfy { $0.text.hasSuffix("。") })
    }

    @Test("Chinese text chunks without losing characters")
    func chineseChunking() {
        let text = String(repeating: "中文测试句子。", count: 60)
        let chunks = chunker.chunks(for: paragraphs(text), maxCharacters: 200)

        #expect(chunks.count > 1)
        #expect(chunks.map(\.text).joined().replacingOccurrences(of: " ", with: "") == text)
    }

    @Test("Right-to-left text chunks cleanly")
    func arabicChunking() {
        let sentence = "هذه جملة اختبار قصيرة."
        let chunks = chunker.chunks(for: paragraphs(Array(repeating: sentence, count: 30).joined(separator: " ")), maxCharacters: 200)

        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { !$0.text.isEmpty })
    }

    // MARK: - Determinism

    /// Resume depends entirely on this: after a relaunch the queue re-chunks the
    /// source and trusts that chunk N is the same text it was before.
    @Test("Chunking is deterministic across runs")
    func deterministicAcrossRuns() {
        let doc = paragraphs(
            Array(repeating: "The first paragraph sentence.", count: 30).joined(separator: " "),
            Array(repeating: "The second paragraph sentence.", count: 30).joined(separator: " ")
        )

        let first = chunker.chunks(for: doc, maxCharacters: 400)
        let second = TextChunker().chunks(for: doc, maxCharacters: 400)

        #expect(first == second)
    }

    @Test("A different limit is a different chunking")
    func limitChangesChunking() {
        let doc = paragraphs(Array(repeating: "A sentence here.", count: 40).joined(separator: " "))

        #expect(chunker.chunks(for: doc, maxCharacters: 400) != chunker.chunks(for: doc, maxCharacters: 800))
    }
}

@Suite("Chunk boundary policy")
struct ChunkBoundaryTests {
    private let chunker = TextChunker()

    private func sectioned(sections: Int, paragraphsEach: Int) -> ExtractedDocument {
        var blocks: [DocumentBlock] = []
        for section in 1...sections {
            blocks.append(DocumentBlock(kind: .heading(level: 2), text: "Section \(section)"))
            for paragraph in 1...paragraphsEach {
                blocks.append(DocumentBlock(
                    kind: .paragraph,
                    text: "Paragraph \(paragraph) of section \(section). It is short enough to pack with its neighbours."
                ))
            }
        }
        return ExtractedDocument(
            suggestedTitle: "Doc",
            blocks: blocks,
            characterCount: blocks.reduce(0) { $0 + $1.text.count },
            detectedLanguage: nil
        )
    }

    /// The default is unchanged, so the built-in engine keeps every pause.
    @Test("everyBlock gives one chunk per block")
    func everyBlockIsUnchanged() {
        let document = sectioned(sections: 4, paragraphsEach: 3)

        let chunks = chunker.chunks(for: document, maxCharacters: 2500, boundary: .everyBlock)

        #expect(chunks.count == document.blocks.count)
        #expect(chunks.allSatisfy { $0.startsBlock })
    }

    @Test("everyBlock is the default")
    func everyBlockIsDefault() {
        let document = sectioned(sections: 3, paragraphsEach: 2)

        let defaulted = chunker.chunks(for: document, maxCharacters: 2500)
        let explicit = chunker.chunks(for: document, maxCharacters: 2500, boundary: .everyBlock)

        #expect(defaulted == explicit)
    }

    /// The point of the policy: paragraphs pack, so a document of short
    /// paragraphs stops costing one request each.
    @Test("headingsOnly packs consecutive paragraphs together")
    func headingsOnlyPacks() {
        let document = sectioned(sections: 6, paragraphsEach: 5)

        let everyBlock = chunker.chunks(for: document, maxCharacters: 2500, boundary: .everyBlock)
        let headingsOnly = chunker.chunks(for: document, maxCharacters: 2500, boundary: .headingsOnly)

        #expect(everyBlock.count == 36)
        #expect(headingsOnly.count == 12, "6 headings + 6 packed paragraph runs")
    }

    /// A heading running into its own body text is the pause whose absence
    /// sounds broken rather than merely flat, so it survives on both sides.
    @Test("headingsOnly keeps a heading isolated in its own chunk")
    func headingsStayIsolated() {
        let document = sectioned(sections: 3, paragraphsEach: 4)

        let chunks = chunker.chunks(for: document, maxCharacters: 2500, boundary: .headingsOnly)

        let headingChunks = chunks.filter { $0.text.hasPrefix("Section ") }
        #expect(headingChunks.count == 3)
        #expect(headingChunks.allSatisfy { $0.text.contains("Paragraph") == false })
        // Every chunk opens a block: headings break before, and the body that
        // follows a heading breaks after it.
        #expect(chunks.allSatisfy { $0.startsBlock })
    }

    @Test("headingsOnly still never exceeds the target")
    func headingsOnlyRespectsTheTarget() {
        let document = sectioned(sections: 3, paragraphsEach: 40)
        let target = Int(2500 * TextChunker.fillRatio)

        let chunks = chunker.chunks(for: document, maxCharacters: 2500, boundary: .headingsOnly)

        #expect(chunks.allSatisfy { $0.text.count <= target })
        // Packing that overflows mid-run continues the block rather than opening
        // a new one, so those chunks carry no pause.
        #expect(chunks.contains { !$0.startsBlock })
    }

    @Test("headingsOnly loses no text")
    func headingsOnlyPreservesText() {
        let document = sectioned(sections: 3, paragraphsEach: 3)

        let everyBlock = chunker.chunks(for: document, maxCharacters: 2500, boundary: .everyBlock)
        let headingsOnly = chunker.chunks(for: document, maxCharacters: 2500, boundary: .headingsOnly)

        #expect(headingsOnly.map(\.text).joined(separator: " ") == everyBlock.map(\.text).joined(separator: " "))
    }

    /// Resume depends on it: same document, same limit, same policy → same chunks.
    @Test("headingsOnly is deterministic")
    func headingsOnlyIsDeterministic() {
        let document = sectioned(sections: 5, paragraphsEach: 4)

        let first = chunker.chunks(for: document, maxCharacters: 2500, boundary: .headingsOnly)
        let second = TextChunker().chunks(for: document, maxCharacters: 2500, boundary: .headingsOnly)

        #expect(first == second)
    }

    @Test("a document with no headings packs into as few chunks as fit")
    func headinglessDocumentPacks() {
        let blocks = (1...30).map {
            DocumentBlock(kind: .paragraph, text: "Paragraph number \($0) with a little text in it.")
        }
        let document = ExtractedDocument(
            suggestedTitle: "Doc",
            blocks: blocks,
            characterCount: blocks.reduce(0) { $0 + $1.text.count },
            detectedLanguage: nil
        )

        let chunks = chunker.chunks(for: document, maxCharacters: 2500, boundary: .headingsOnly)

        #expect(chunks.count == 1)
    }
}
