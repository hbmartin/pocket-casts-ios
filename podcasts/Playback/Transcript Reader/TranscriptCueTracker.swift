import Foundation

/// Resolves the cue containing a playback/reference position in O(1) amortized
/// for normal forward playback by remembering the last matched index instead of
/// scanning from the start on every tick.
///
/// This mirrors `TranscriptViewController.currentCue(at:in:)` exactly (including
/// falling back to a full scan only on backward seeks, and resolving overlapping
/// cues to the earliest match). It is deliberately a standalone copy rather than
/// a helper shared with the view controller: the VC's version is private state
/// tangled with its display-link lifecycle, and extracting it would mean
/// restructuring a file this feature is required to leave surgically intact.
/// The algorithm is ~25 lines and is covered by unit tests here.
nonisolated struct TranscriptCueTracker: Sendable {

    private var cachedCueIndex: Int = 0

    /// Returns the index (into `cues`) of the cue containing `position`, or nil
    /// when no cue contains it.
    mutating func cueIndex(at position: Double, in cues: [TranscriptCue]) -> Int? {
        guard !cues.isEmpty else { return nil }
        let cached = min(cachedCueIndex, cues.count - 1)

        if cues[cached].contains(timeInSeconds: position) {
            // Earliest-match semantics: overlapping earlier cues win, exactly as
            // the view controller's `first { contains }` scan behaves.
            var index = cached
            while index > 0, cues[index - 1].contains(timeInSeconds: position) {
                index -= 1
            }
            cachedCueIndex = index
            return index
        }

        // Backward seek — match `first { contains }` semantics so overlapping
        // cues resolve to the earliest match.
        if position < cues[cached].startTime {
            if let index = cues.firstIndex(where: { $0.contains(timeInSeconds: position) }) {
                cachedCueIndex = index
                return index
            }
            return nil
        }

        var i = cached + 1
        while i < cues.count, cues[i].startTime <= position {
            if cues[i].contains(timeInSeconds: position) {
                cachedCueIndex = i
                return i
            }
            i += 1
        }

        // Overlap edge case: an earlier long cue can contain a position the
        // cached-and-forward walk missed. Full scan preserves exact semantics.
        if let index = cues.firstIndex(where: { $0.contains(timeInSeconds: position) }) {
            cachedCueIndex = index
            return index
        }
        return nil
    }

    mutating func reset() {
        cachedCueIndex = 0
    }
}
