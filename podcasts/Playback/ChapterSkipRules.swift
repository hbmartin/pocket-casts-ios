import Foundation

/// Pure matching logic for chapter smart skip: a chapter is auto-deselected when its title
/// contains any of the podcast's configured patterns (case-insensitive, whitespace-trimmed).
/// Kept nonisolated and side-effect free so it can be unit tested directly.
nonisolated enum ChapterSkipRules {
    /// Returns true when `title` contains any of `patterns` as a case-insensitive substring.
    /// Patterns and the title are compared after trimming surrounding whitespace; empty or
    /// whitespace-only patterns never match.
    static func matches(title: String, patterns: [String]) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }

        return patterns.contains { pattern in
            let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPattern.isEmpty else { return false }

            return trimmedTitle.range(of: trimmedPattern, options: [.caseInsensitive]) != nil
        }
    }

    /// Applies the rules to a loaded chapter list: any still-playable chapter whose title matches
    /// is marked `shouldPlay = false`, except chapter indices the user re-enabled this session.
    /// Returns the indices that were deselected by a rule (for analytics).
    @discardableResult
    static func apply(to chapters: [ChapterInfo], patterns: [String], reEnabledIndices: Set<Int>) -> Set<Int> {
        guard !patterns.isEmpty else { return [] }

        var ruleSkipped = Set<Int>()
        for chapter in chapters where chapter.shouldPlay {
            guard !reEnabledIndices.contains(chapter.index) else { continue }

            if matches(title: chapter.title, patterns: patterns) {
                chapter.shouldPlay = false
                ruleSkipped.insert(chapter.index)
            }
        }
        return ruleSkipped
    }
}
