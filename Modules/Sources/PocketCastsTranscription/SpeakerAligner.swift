import Foundation

/// Merges ASR output (what was said, when) with diarizer output (who spoke, when)
/// into display cues. Pure function — no IO, no state — so it can be exhaustively
/// unit-tested; this is the correctness core of the transcription pipeline.
public enum SpeakerAligner {
    /// Tunable thresholds for `align(segments:turns:options:)`. Defaults are the
    /// product-approved values; tests inject variants.
    public struct Options: Sendable {
        /// Max |turn midpoint − unit midpoint| for assigning a speaker to a unit
        /// that overlaps no turn at all (inclusive).
        public var gapTolerance: TimeInterval
        /// Pause (strictly greater than) after sentence-final punctuation that
        /// breaks a cue.
        public var sentencePause: TimeInterval
        /// Max characters of joined cue text (inclusive; a single oversized unit
        /// still forms its own cue).
        public var maxCueCharacters: Int
        /// Max cue duration in seconds (inclusive; a single oversized unit still
        /// forms its own cue).
        public var maxCueDuration: TimeInterval

        public init(
            gapTolerance: TimeInterval = 1.0,
            sentencePause: TimeInterval = 0.75,
            maxCueCharacters: Int = 200,
            maxCueDuration: TimeInterval = 15.0
        ) {
            self.gapTolerance = gapTolerance
            self.sentencePause = sentencePause
            self.maxCueCharacters = maxCueCharacters
            self.maxCueDuration = maxCueDuration
        }
    }

    /// Aligns ASR segments with speaker turns:
    ///
    /// 1. Units are words when a segment has word timings, else the segment itself.
    /// 2. Each unit takes the speaker of the turn with maximal temporal overlap;
    ///    ties go to the turn that starts earlier. With zero overlap everywhere,
    ///    the nearest turn midpoint within `gapTolerance` wins, else the previous
    ///    unit's speaker is inherited, else nil.
    /// 3. Consecutive same-speaker units group into cues, breaking after
    ///    sentence-final punctuation followed by a pause > `sentencePause`, or when
    ///    joined text would exceed `maxCueCharacters`, or when the cue would exceed
    ///    `maxCueDuration`.
    /// 4. Speaker IDs normalize to "Speaker 1"…N by order of first appearance.
    /// 5. If at most one distinct speaker was assigned, every cue's speaker is nil
    ///    (clean monologue display — the serializer then omits `<v>` tags).
    public static func align(segments: [ASRSegment], turns: [SpeakerTurn], options: Options = Options()) -> [DiarizedCue] {
        let units = makeUnits(from: segments)
        guard !units.isEmpty else { return [] }

        let rawSpeakers = assignSpeakers(to: units, turns: turns, options: options)
        let speakers = normalize(rawSpeakers)

        return group(units: units, speakers: speakers, options: options)
    }

    // MARK: - Step 1: units

    private struct Unit {
        let text: String
        let start: TimeInterval
        let end: TimeInterval

        var midpoint: TimeInterval { (start + end) / 2 }
    }

    private static func makeUnits(from segments: [ASRSegment]) -> [Unit] {
        // Stable sort by start time; word order inside a segment is canonical text
        // order and is never reordered.
        let ordered = segments.enumerated().sorted { lhs, rhs in
            if lhs.element.start != rhs.element.start { return lhs.element.start < rhs.element.start }
            return lhs.offset < rhs.offset
        }.map(\.element)

        var units: [Unit] = []
        for segment in ordered {
            if let words = segment.words, !words.isEmpty {
                for word in words {
                    let trimmed = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    units.append(Unit(text: trimmed, start: word.start, end: word.end))
                }
            } else {
                let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                units.append(Unit(text: trimmed, start: segment.start, end: segment.end))
            }
        }
        return units
    }

    // MARK: - Step 2: speaker per unit

    private static func assignSpeakers(to units: [Unit], turns: [SpeakerTurn], options: Options) -> [String?] {
        var assigned: [String?] = []
        assigned.reserveCapacity(units.count)

        for unit in units {
            if let overlapping = maximalOverlapTurn(for: unit, in: turns) {
                assigned.append(overlapping.speakerId)
            } else if let nearest = nearestMidpointTurn(for: unit, in: turns, tolerance: options.gapTolerance) {
                assigned.append(nearest.speakerId)
            } else if let previous = assigned.last {
                assigned.append(previous) // Inherit (nil inherits as nil).
            } else {
                assigned.append(nil)
            }
        }
        return assigned
    }

    /// The turn with maximal strictly-positive temporal overlap; ties go to the
    /// earlier turn start.
    private static func maximalOverlapTurn(for unit: Unit, in turns: [SpeakerTurn]) -> SpeakerTurn? {
        var best: (turn: SpeakerTurn, overlap: TimeInterval)?
        for turn in turns {
            let overlap = min(unit.end, turn.end) - max(unit.start, turn.start)
            guard overlap > 0 else { continue }
            if let current = best {
                if overlap > current.overlap || (overlap == current.overlap && turn.start < current.turn.start) {
                    best = (turn, overlap)
                }
            } else {
                best = (turn, overlap)
            }
        }
        return best?.turn
    }

    /// The turn whose midpoint is nearest the unit's midpoint, if within
    /// `tolerance` (inclusive); ties go to the earlier turn start.
    private static func nearestMidpointTurn(for unit: Unit, in turns: [SpeakerTurn], tolerance: TimeInterval) -> SpeakerTurn? {
        var best: (turn: SpeakerTurn, distance: TimeInterval)?
        for turn in turns {
            let distance = abs((turn.start + turn.end) / 2 - unit.midpoint)
            if let current = best {
                if distance < current.distance || (distance == current.distance && turn.start < current.turn.start) {
                    best = (turn, distance)
                }
            } else {
                best = (turn, distance)
            }
        }
        guard let best, best.distance <= tolerance else { return nil }
        return best.turn
    }

    // MARK: - Steps 4 & 5: normalization (applied before grouping; the mapping is
    // one-to-one, so grouping boundaries are identical either way)

    private static func normalize(_ rawSpeakers: [String?]) -> [String?] {
        var names: [String: String] = [:]
        var normalized: [String?] = []
        normalized.reserveCapacity(rawSpeakers.count)

        for raw in rawSpeakers {
            guard let raw else {
                normalized.append(nil)
                continue
            }
            if let existing = names[raw] {
                normalized.append(existing)
            } else {
                let name = "Speaker \(names.count + 1)"
                names[raw] = name
                normalized.append(name)
            }
        }

        // At most one distinct speaker: emit nil everywhere for a clean monologue.
        if names.count <= 1 {
            return Array(repeating: nil, count: rawSpeakers.count)
        }
        return normalized
    }

    // MARK: - Step 3: cue grouping

    private static func group(units: [Unit], speakers: [String?], options: Options) -> [DiarizedCue] {
        var cues: [DiarizedCue] = []

        var speaker: String?
        var text = ""
        var start: TimeInterval = 0
        var end: TimeInterval = 0
        var lastUnitText = ""

        func flush() {
            guard !text.isEmpty else { return }
            cues.append(DiarizedCue(speaker: speaker, text: text, start: start, end: end))
            text = ""
        }

        for (unit, unitSpeaker) in zip(units, speakers) {
            if text.isEmpty {
                (speaker, text, start, end, lastUnitText) = (unitSpeaker, unit.text, unit.start, unit.end, unit.text)
                continue
            }

            let joined = text + " " + unit.text
            let shouldBreak = unitSpeaker != speaker
                || (endsSentence(lastUnitText) && unit.start - end > options.sentencePause)
                || joined.count > options.maxCueCharacters
                || unit.end - start > options.maxCueDuration

            if shouldBreak {
                flush()
                (speaker, text, start, end, lastUnitText) = (unitSpeaker, unit.text, unit.start, unit.end, unit.text)
            } else {
                text = joined
                end = max(end, unit.end)
                lastUnitText = unit.text
            }
        }
        flush()
        return cues
    }

    private static let sentenceTerminators: Set<Character> = [".", "!", "?", "…"]
    private static let trailingWrappers: Set<Character> = ["\"", "'", "\u{201D}", "\u{2019}", ")", "]"]

    /// True when `text` ends with sentence-final punctuation, ignoring trailing
    /// closing quotes/brackets (e.g. `Really?"` counts).
    static func endsSentence(_ text: String) -> Bool {
        var remainder = Substring(text)
        while let last = remainder.last, trailingWrappers.contains(last) {
            remainder = remainder.dropLast()
        }
        guard let last = remainder.last else { return false }
        return sentenceTerminators.contains(last)
    }
}
