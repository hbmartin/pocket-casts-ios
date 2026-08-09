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
    /// can't produce single-word chunks. Never allowed to push the target past
    /// the stated limit itself — the limit is a hard cap.
    static let minimumTarget = 200

    public init() {}

    /// - Parameter maxCharacters: the engine's hard per-request limit.
    /// - Parameter boundary: which block boundaries must end a chunk. Comes from
    ///   the engine's capabilities, and the engine is frozen on the narration
    ///   row, so a resumed run always re-chunks the same way.
    public func chunks(
        for document: ExtractedDocument,
        maxCharacters: Int,
        boundary: ChunkBoundary = .everyBlock
    ) -> [NarrationChunk] {
        let target = min(
            max(Int(Double(maxCharacters) * Self.fillRatio), Self.minimumTarget),
            max(maxCharacters, 1)
        )
        var chunks: [NarrationChunk] = []
        var pending = ""
        var pendingStartsBlock = true
        var previousWasHeading = false

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
            // Rule 2, as far as this engine wants it. A heading always breaks on
            // both sides — before it so it is set off from what came before, and
            // after it so it does not run into its own body text, which is the
            // one missing pause that sounds broken rather than merely flat.
            let mustBreak = switch boundary {
            case .everyBlock: true
            case .headingsOnly: block.isHeading || previousWasHeading
            }
            if mustBreak {
                flush(nextStartsBlock: true)
            }
            previousWasHeading = block.isHeading

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
    /// pause in an odd place. The split operates on ranges of the original text
    /// rather than reconstructing `NLTokenizer` word tokens: word token ranges
    /// omit punctuation, which used to silently turn `hello, world!` into
    /// `hello world` whenever an overlong sentence was split.
    static func fitting(_ sentence: String, within target: Int) -> [String] {
        guard sentence.count > target else { return [sentence] }

        var pieces: [String] = []
        var remaining = sentence[...]

        while remaining.count > target {
            while let first = remaining.first, first.isWhitespace {
                remaining.removeFirst()
            }
            guard !remaining.isEmpty else { break }

            let hardEnd = remaining.index(remaining.startIndex, offsetBy: target)
            let candidate = remaining[..<hardEnd]
            let whitespace = candidate.lastIndex(where: \Character.isWhitespace)
            let split = whitespace == remaining.startIndex ? nil : whitespace
            let end = split ?? hardEnd

            let piece = String(remaining[..<end])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty {
                pieces.append(piece)
            }
            remaining = remaining[end...]
        }

        let tail = String(remaining).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            pieces.append(tail)
        }
        return pieces
    }
}
