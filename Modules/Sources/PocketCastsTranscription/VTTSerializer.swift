import Foundation

/// Serializes diarized cues to WebVTT — the canonical on-disk transcript artifact.
/// Output must stay parseable by the app's existing `TranscriptModel` VTT path
/// (voice spans as `<v Speaker N>`), which is what makes the whole existing
/// render/search/highlight/tap-to-seek stack work unchanged.
public enum VTTSerializer {
    /// Minimum duration enforced on zero/negative-length cues (some parsers drop
    /// cues whose end doesn't exceed their start).
    private static let minimumCueDuration: TimeInterval = 0.010

    public static func serialize(_ transcript: DiarizedTranscript) -> String {
        serialize(cues: transcript.cues)
    }

    public static func serialize(cues: [DiarizedCue]) -> String {
        var output = "WEBVTT\n"
        for cue in cues {
            let start = max(cue.start, 0)
            var end = max(cue.end, start)
            if end <= start {
                end = start + minimumCueDuration
            }

            output += "\n"
            output += "\(timestamp(start)) --> \(timestamp(end))\n"

            let text = escape(flattened(cue.text))
            if let speaker = cue.speaker {
                output += "<v \(escape(speaker))>\(text)\n"
            } else {
                output += "\(text)\n"
            }
        }
        return output
    }

    /// `HH:MM:SS.mmm`, hours zero-padded to at least two digits and unbounded
    /// above (a 100-hour cue serializes as `100:00:00.000`).
    static func timestamp(_ seconds: TimeInterval) -> String {
        let totalMilliseconds = Int((seconds * 1000).rounded())
        let milliseconds = totalMilliseconds % 1000
        let totalSeconds = totalMilliseconds / 1000
        let secs = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, secs, milliseconds)
    }

    /// Escapes the characters WebVTT reserves in cue payload text.
    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Collapses newline runs to single spaces: a blank line inside a payload
    /// would terminate the cue early.
    private static func flattened(_ text: String) -> String {
        guard text.contains(where: \.isNewline) else { return text }
        return text
            .split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
    }
}
