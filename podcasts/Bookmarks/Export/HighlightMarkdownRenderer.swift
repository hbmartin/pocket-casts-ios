import Foundation

/// Renders one episode's highlights as a PKM-ready Markdown document
/// (Highlights program S5): YAML frontmatter + one block per highlight with
/// the excerpt as a quote, a time-linked timestamp, title, and `#tags`.
///
/// Pure — episode/podcast titles, share links and tags arrive resolved — so it
/// is directly unit-testable, like `BookmarkMarkdownExporter` before it.
/// The share-sheet "Export as Markdown" flow keeps that exporter; this renderer
/// backs the folder auto-export where one stable file per episode lets
/// Obsidian-style vaults diff and backlink cleanly.
nonisolated struct HighlightMarkdownRenderer {
    struct ResolvedHighlight {
        let title: String
        let time: TimeInterval
        let endTime: TimeInterval?
        let created: Date
        let excerpt: String?
        let tags: [String]
        /// Time-linked share URL; nil for content that has no public share page.
        let shareLink: String?
    }

    struct EpisodeExport {
        let podcastTitle: String
        let episodeTitle: String
        let episodeUuid: String
        let highlights: [ResolvedHighlight]
    }

    var locale = Locale.current
    var timeZone = TimeZone.current

    /// Hook for `[[Wikilink]]`-style enrichment of excerpt text once the
    /// Mentioned Entity substrate lands (S10). Identity until then.
    var excerptTransform: (String) -> String = { $0 }

    func markdown(for export: EpisodeExport) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        dateFormatter.locale = locale
        dateFormatter.timeZone = timeZone

        let allTags = orderedUnion(export.highlights.map(\.tags))

        var lines: [String] = ["---"]
        lines.append("podcast: \(yamlEscape(export.podcastTitle))")
        lines.append("episode: \(yamlEscape(export.episodeTitle))")
        lines.append("episode_uuid: \(export.episodeUuid)")
        if !allTags.isEmpty {
            lines.append("tags: [\(allTags.map(yamlEscape).joined(separator: ", "))]")
        }
        lines.append("---")
        lines.append("")
        lines.append("# \(escape(export.episodeTitle))")
        lines.append("")

        for highlight in export.highlights {
            let timestamp = Self.timestamp(highlight.time)
            let timePart = highlight.shareLink.map { "[\(timestamp)](\($0))" } ?? timestamp
            lines.append("## \(timePart) \(escape(highlight.title))")
            lines.append("")

            if let excerpt = highlight.excerpt, !excerpt.isEmpty {
                lines.append("> \(excerptTransform(excerpt))")
                lines.append("")
            }

            var footer: [String] = []
            if !highlight.tags.isEmpty {
                footer.append(highlight.tags.map { "#\(hashtagSafe($0))" }.joined(separator: " "))
            }
            footer.append(dateFormatter.string(from: highlight.created))
            lines.append(footer.joined(separator: " — "))
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// `<Podcast>/<Episode>.md`, sanitized for the file system.
    func relativePath(for export: EpisodeExport) -> String {
        "\(sanitized(export.podcastTitle))/\(sanitized(export.episodeTitle)).md"
    }

    // MARK: - Helpers

    static func timestamp(_ time: TimeInterval) -> String {
        let total = Int(time.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    /// Case-insensitive union preserving first appearance order, then sorted
    /// for stable output.
    private func orderedUnion(_ tagSets: [[String]]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tagSets.flatMap({ $0 }) {
            let key = tag.lowercased()
            if seen.insert(key).inserted { result.append(tag) }
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Minimal Markdown escaping for user text in headings.
    private func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    private func yamlEscape(_ text: String) -> String {
        "\"\(text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    /// Tags render as `#tag`; whitespace would break the hashtag, so it folds
    /// to hyphens (the common Obsidian convention).
    private func hashtagSafe(_ tag: String) -> String {
        tag.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: "-")
    }

    /// File-system-safe single path component.
    private func sanitized(_ component: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = component.components(separatedBy: invalid).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : String(cleaned.prefix(120))
    }
}
