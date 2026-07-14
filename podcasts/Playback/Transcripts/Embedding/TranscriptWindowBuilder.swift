import Foundation
import PocketCastsDataModel

/// Pure segmentation of corpus segments into Embedding Windows: runs of
/// consecutive segments accumulated to a target character size, with a small
/// segment overlap between windows so a thought spanning a boundary lands in
/// at least one window whole. ~1,000 characters keeps a window safely under
/// NLContextualEmbedding's token ceiling.
nonisolated enum TranscriptWindowBuilder {

    struct Window: Equatable, Sendable {
        let windowIndex: Int
        let startSegmentIndex: Int
        let endSegmentIndex: Int
        let text: String
        let startTime: Double
        let endTime: Double?
    }

    static let targetCharacters = 1000
    static let overlapSegments = 2
    /// A final fragment smaller than this merges into the previous window
    /// instead of standing alone (too little context to embed usefully).
    static let minimumCharacters = 120

    /// The head of a window's text stored as the semantic hit's snippet.
    static let previewCharacters = 280

    static func windows(from segments: [TranscriptSearchSegment],
                        targetCharacters: Int = targetCharacters,
                        overlapSegments: Int = overlapSegments,
                        minimumCharacters: Int = minimumCharacters) -> [Window] {
        guard !segments.isEmpty else { return [] }

        var windows: [Window] = []
        var startPosition = 0

        while startPosition < segments.count {
            var characterCount = 0
            var endPosition = startPosition
            while endPosition < segments.count {
                characterCount += segments[endPosition].text.count + (endPosition == startPosition ? 0 : 1)
                if characterCount >= targetCharacters { break }
                endPosition += 1
            }
            endPosition = min(endPosition, segments.count - 1)

            let slice = segments[startPosition ... endPosition]
            let window = Window(
                windowIndex: windows.count,
                startSegmentIndex: slice.first!.index,
                endSegmentIndex: slice.last!.index,
                text: slice.map(\.text).joined(separator: " "),
                startTime: slice.first!.startTime,
                endTime: slice.last!.endTime ?? slice.last!.startTime
            )

            // A runt tail merges into the previous window rather than standing alone.
            if window.text.count < minimumCharacters, let previous = windows.popLast() {
                windows.append(Window(
                    windowIndex: previous.windowIndex,
                    startSegmentIndex: previous.startSegmentIndex,
                    endSegmentIndex: window.endSegmentIndex,
                    text: previous.text + " " + window.text,
                    startTime: previous.startTime,
                    endTime: window.endTime
                ))
            } else {
                windows.append(window)
            }

            guard endPosition < segments.count - 1 else { break }
            // Next window re-covers the last `overlapSegments` segments.
            startPosition = max(endPosition + 1 - overlapSegments, startPosition + 1)
        }

        return windows
    }

    static func preview(of text: String) -> String {
        guard text.count > previewCharacters else { return text }
        let cut = text.prefix(previewCharacters)
        if let lastSpace = cut.lastIndex(of: " ") {
            return String(cut[..<lastSpace])
        }
        return String(cut)
    }
}
