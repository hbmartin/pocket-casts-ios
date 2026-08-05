import Foundation
import NaturalLanguage

/// Packs an extracted document into synthesis-sized chunks.
///
/// Three rules, in priority order:
///
/// 1. **Never split a sentence.** A synthesizer decides intonation from the
///    whole sentence, so a sentence cut in half is audibly wrong at the seam —
///    far worse than a chunk that runs slightly under target.
/// 2. **A block boundary always ends a chunk.** Paragraphs and headings are
///    where the assembler inserts pauses, so they have to fall on chunk edges.
/// 3. **Fill greedily up to the target**, which is deliberately under the
///    engine's hard limit (see `fillRatio`).
///
/// Chunking is pure and deterministic: the same document and limit always
/// produce the same chunks with the same indices. That is what makes resume
/// work — the queue re-chunks after a relaunch and trusts index N to mean the
/// same text it meant before.
public struct TextChunker: Sendable {
    /// Fraction of the engine's stated limit to actually fill. The slack absorbs
    /// the mismatch between how we count characters and how a provider counts
    /// them (normalization, escaping, SSML wrappers), so a chunk that measures
    /// just under the limit here can't come back as a 413 from the provider.
    static let fillRatio = 0.8

    /// Floor for the effective target, so a pathologically small stated limit
    /// can't produce single-word chunks.
    static let minimumTarget = 200

    public init() {}

    /// - Parameter maxCharacters: the engine's hard per-request limit.
    public func chunks(for document: ExtractedDocument, maxCharacters: Int) -> [NarrationChunk] {
        let target = max(Int(Double(maxCharacters) * Self.fillRatio), Self.minimumTarget)
        var chunks: [NarrationChunk] = []
        var pending = ""
        var pendingStartsBlock = true

        /// Emits whatever has accumulated. `nextStartsBlock` records why we're
        /// flushing: at a block boundary the following chunk opens a new block
        /// (and earns a pause), whereas a chunk that simply filled up leaves the
        /// following one mid-block.
        func flush(nextStartsBlock: Bool) {
            if !pending.isEmpty {
                chunks.append(NarrationChunk(index: chunks.count, text: pending, startsBlock: pendingStartsBlock))
                pending = ""
            }
            pendingStartsBlock = nextStartsBlock
        }

        for block in document.blocks {
            // Rule 2: whatever was accumulating ends here.
            flush(nextStartsBlock: true)

            for sentence in Self.sentences(in: block.text) {
                for piece in Self.fitting(sentence, within: target) {
                    if pending.isEmpty {
                        pending = piece
                    } else if pending.count + 1 + piece.count <= target {
                        pending += " " + piece
                    } else {
                        flush(nextStartsBlock: false)
                        pending = piece
                    }
                }
            }
        }
        flush(nextStartsBlock: false)

        return chunks
    }

    // MARK: - Sentence segmentation

    /// `NLTokenizer` rather than punctuation splitting: it handles abbreviations
    /// ("Dr. Smith"), decimals, and languages that don't delimit sentences with
    /// a period at all — CJK text has no spaces and its own terminators.
    static func sentences(in text: String) -> [String] {
        // Whitespace-only input has nothing to say. Guarding here rather than
        // trusting extractors keeps a stray blank block from becoming a chunk
        // that renders to silence and still costs an API call.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { sentences.append(sentence) }
            return true
        }
        // A string the tokenizer declines to split (rare, but possible for
        // symbol-only input) is still one sentence's worth of text.
        return sentences.isEmpty ? [trimmed] : sentences
    }

    /// Splits a single sentence that is itself longer than the target.
    ///
    /// This breaks rule 1, which is why it only ever runs when rule 1 is
    /// impossible to keep — a 3,000-character "sentence" with no terminator, or
    /// a wall of CJK text. Breaking at word boundaries keeps the damage to a
    /// pause in an odd place; word tokenization is used rather than splitting on
    /// spaces so that scripts without spaces still break somewhere legible.
    static func fitting(_ sentence: String, within target: Int) -> [String] {
        guard sentence.count > target else { return [sentence] }

        var pieces: [String] = []
        var current = ""

        for word in words(in: sentence) {
            if current.isEmpty {
                current = word
            } else if current.count + 1 + word.count <= target {
                current += " " + word
            } else {
                pieces.append(current)
                current = word
            }

            // A single "word" longer than the target (a URL, a base64 blob, an
            // unbroken CJK run the tokenizer kept whole) has to be cut by
            // character or it would never fit.
            while current.count > target {
                let cut = current.index(current.startIndex, offsetBy: target)
                pieces.append(String(current[..<cut]))
                current = String(current[cut...])
            }
        }
        if !current.isEmpty { pieces.append(current) }

        return pieces
    }

    private static func words(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var words: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !word.isEmpty { words.append(word) }
            return true
        }
        return words.isEmpty ? [text] : words
    }
}
