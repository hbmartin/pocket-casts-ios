import Foundation

/// A renderable unit of the transcript reader: either a speaker header derived
/// from the `.transcriptSpeaker` attribute runs, or a paragraph of transcript
/// text (backed by a `TranscriptCue` when the transcript has timing info).
nonisolated struct TranscriptReaderBlock: Identifiable, Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case speaker(name: String)
        /// `cueIndex` is an index into `TranscriptModel.cues`, or nil for
        /// cue-less transcripts (e.g. HTML) that have no timing info.
        case paragraph(cueIndex: Int?)
    }

    /// Sequential position in the blocks array (usable as an array index).
    let id: Int
    let kind: Kind
    /// The block's text with leading/trailing whitespace and newlines removed.
    let text: String
    /// Where `text` sits inside the full transcript plain text, in UTF-16
    /// units (same convention as `TranscriptCue.characterRange`).
    let rangeInFullText: NSRange

    var cueIndex: Int? {
        if case .paragraph(let index) = kind { return index }
        return nil
    }

    var speakerName: String? {
        if case .speaker(let name) = kind { return name }
        return nil
    }
}

/// Builds reader blocks from a `TranscriptModel`. Pure and nonisolated so the
/// block-building logic is unit-testable off the main actor.
nonisolated enum TranscriptReaderContent {

    static func makeBlocks(from model: TranscriptModel) -> [TranscriptReaderBlock] {
        let ns = model.nsAttributedText
        let full = ns.string as NSString
        guard full.length > 0 else { return [] }

        enum Element {
            case speaker(String)
            case cue(Int)
        }

        var elements: [(range: NSRange, element: Element)] = []
        ns.enumerateAttribute(.transcriptSpeaker, in: NSRange(location: 0, length: ns.length)) { value, range, _ in
            if let name = value as? String {
                elements.append((range, .speaker(name)))
            }
        }
        for (index, cue) in model.cues.enumerated() {
            elements.append((cue.characterRange, .cue(index)))
        }
        elements.sort { $0.range.location < $1.range.location }

        guard !elements.isEmpty else {
            // Cue-less transcripts (e.g. HTML): render one paragraph per line.
            return lineBlocks(from: full)
        }

        var blocks: [TranscriptReaderBlock] = []
        for entry in elements {
            guard let trimmed = trimmedRange(of: entry.range, in: full) else { continue }
            let text = full.substring(with: trimmed)
            switch entry.element {
            case .speaker(let name):
                blocks.append(TranscriptReaderBlock(id: blocks.count, kind: .speaker(name: name), text: text, rangeInFullText: trimmed))
            case .cue(let index):
                blocks.append(TranscriptReaderBlock(id: blocks.count, kind: .paragraph(cueIndex: index), text: text, rangeInFullText: trimmed))
            }
        }
        return blocks
    }

    private static func lineBlocks(from full: NSString) -> [TranscriptReaderBlock] {
        var blocks: [TranscriptReaderBlock] = []
        var location = 0
        while location < full.length {
            let lineRange = full.lineRange(for: NSRange(location: location, length: 0))
            if let trimmed = trimmedRange(of: lineRange, in: full) {
                blocks.append(
                    TranscriptReaderBlock(
                        id: blocks.count,
                        kind: .paragraph(cueIndex: nil),
                        text: full.substring(with: trimmed),
                        rangeInFullText: trimmed
                    )
                )
            }
            location = NSMaxRange(lineRange)
        }
        return blocks
    }

    /// Shrinks `range` so it excludes leading/trailing whitespace and newlines.
    /// Returns nil when the range is invalid or contains only whitespace.
    private static func trimmedRange(of range: NSRange, in text: NSString) -> NSRange? {
        guard range.location != NSNotFound, range.location >= 0, NSMaxRange(range) <= text.length else { return nil }
        let whitespace = CharacterSet.whitespacesAndNewlines as NSCharacterSet
        var start = range.location
        var end = NSMaxRange(range)
        while start < end, whitespace.characterIsMember(text.character(at: start)) {
            start += 1
        }
        while end > start, whitespace.characterIsMember(text.character(at: end - 1)) {
            end -= 1
        }
        guard start < end else { return nil }
        return NSRange(location: start, length: end - start)
    }
}

/// Assembles the shareable text for a transcript quote: the quoted cue text,
/// an episode-title attribution, and a time-anchored share link.
nonisolated enum TranscriptQuoteBuilder {

    /// - Parameters:
    ///   - startTime: the cue's start time in seconds; appended to the link as
    ///     `?t=<whole seconds>` (matching the `?t=` anchor used by
    ///     `SharingModal.Option.currentPosition`). Omitted when nil.
    static func quoteText(cueText: String, episodeTitle: String?, shareURLString: String?, startTime: Double?) -> String {
        var lines: [String] = []

        var quote = "\u{201C}\(cueText.trimmingCharacters(in: .whitespacesAndNewlines))\u{201D}"
        if let episodeTitle = episodeTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !episodeTitle.isEmpty {
            quote += " — \(episodeTitle)"
        }
        lines.append(quote)

        if let shareURLString, !shareURLString.isEmpty {
            if let startTime, startTime.isFinite, startTime >= 0 {
                lines.append("\(shareURLString)?t=\(Int(startTime.rounded()))")
            } else {
                lines.append(shareURLString)
            }
        }

        return lines.joined(separator: "\n")
    }
}
