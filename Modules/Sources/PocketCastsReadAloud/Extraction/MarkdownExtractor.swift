import Foundation
import UniformTypeIdentifiers

/// `.md`: Markdown reduced to what a voice should actually say.
///
/// The governing rule is that markup is *scaffolding, not content*. A narrator
/// saying "hash hash Introduction" or reading a URL aloud character by character
/// is worse than useless, so syntax is stripped, link targets are dropped in
/// favour of their text, and code fences are removed entirely — nobody wants a
/// shell script narrated. Headings survive as their own block kind because they
/// are real structure: they earn a pause now and can become chapters later.
public struct MarkdownExtractor: TextExtractor {
    public let supportedTypes: [UTType] = [.readAloudMarkdown]
    public let supportedFilenameExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]

    public init() {}

    public func extract(data: Data, filename: String?) throws -> ExtractedDocument {
        guard let decoded = TextEncodingSniffer.decode(data) else {
            throw ReadAloudError.undecodableText
        }
        return try ExtractedDocumentBuilder.build(blocks: Self.blocks(in: decoded.text), filename: filename)
    }

    // MARK: - Block pass

    static func blocks(in markdown: String) -> [DocumentBlock] {
        var blocks: [DocumentBlock] = []
        var paragraph: [String] = []
        var fenceMarker: Character?
        var lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // YAML front matter is metadata for the publishing tool, never prose.
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let close = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            lines.removeSubrange(0...close)
        }

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let text = inlineStripped(paragraph.joined(separator: " "))
            if !text.isEmpty {
                blocks.append(DocumentBlock(kind: .paragraph, text: text))
            }
            paragraph.removeAll()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code: swallow everything up to the closing fence. Checked
            // first so nothing inside a fence is interpreted as markup.
            if let marker = fenceMarker {
                if trimmed.count >= 3, trimmed.allSatisfy({ $0 == marker }) { fenceMarker = nil }
                continue
            }
            if trimmed.count >= 3, let marker = trimmed.first, marker == "`" || marker == "~", trimmed.prefix(3).allSatisfy({ $0 == marker }) {
                flushParagraph()
                fenceMarker = marker
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            // Link reference definitions ("[ref]: https://…") are never spoken.
            if isReferenceDefinition(trimmed) { continue }

            // Setext heading: the underline retroactively promotes the pending
            // paragraph. Checked BEFORE thematic breaks because "---" is both,
            // and a "---" directly under a line of text is the heading reading —
            // testing breaks first would swallow every setext H2.
            //
            // Restricted to a single pending line: promoting a multi-line
            // paragraph to a heading would turn prose into a title. CommonMark
            // allows it; narration is better off without it.
            if paragraph.count == 1, let level = setextLevel(trimmed) {
                let text = inlineStripped(paragraph[0])
                paragraph.removeAll()
                if !text.isEmpty {
                    blocks.append(DocumentBlock(kind: .heading(level: level), text: text))
                }
                continue
            }

            // Thematic breaks end a paragraph and say nothing themselves.
            if isThematicBreak(trimmed) {
                flushParagraph()
                continue
            }

            if let (level, text) = atxHeading(trimmed) {
                flushParagraph()
                let stripped = inlineStripped(text)
                if !stripped.isEmpty {
                    blocks.append(DocumentBlock(kind: .heading(level: level), text: stripped))
                }
                continue
            }

            // A list item is its own block: items are separate thoughts, and
            // making each one a block earns it a pause instead of running the
            // whole list together into one breathless sentence.
            if let item = listItemBody(trimmed) {
                flushParagraph()
                let text = inlineStripped(item)
                if !text.isEmpty {
                    blocks.append(DocumentBlock(kind: .paragraph, text: text))
                }
                continue
            }

            if let row = tableRowBody(trimmed) {
                flushParagraph()
                if !row.isEmpty {
                    blocks.append(DocumentBlock(kind: .paragraph, text: row))
                }
                continue
            }

            paragraph.append(blockquoteStripped(trimmed))
        }
        flushParagraph()

        return blocks
    }

    // MARK: - Line classification

    private static func atxHeading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix(while: { $0 == "#" })
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = line.dropFirst(hashes.count)
        // "#hashtag" is not a heading — ATX requires a space after the hashes.
        guard rest.first?.isWhitespace == true || rest.isEmpty else { return nil }
        // Closing hashes ("## Title ##") are decoration, but only when a space
        // precedes them — the hash in "## Learning C#" is content.
        let body = rest.trimmingCharacters(in: .whitespaces)
        let withoutClosing = body.replacingOccurrences(of: "\\s+#+$", with: "", options: .regularExpression)
        return (hashes.count, withoutClosing.trimmingCharacters(in: .whitespaces))
    }

    private static func setextLevel(_ line: String) -> Int? {
        guard line.count >= 2 else { return nil }
        if line.allSatisfy({ $0 == "=" }) { return 1 }
        if line.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        let condensed = line.filter { !$0.isWhitespace }
        guard condensed.count >= 3 else { return false }
        return condensed.allSatisfy { $0 == "*" } || condensed.allSatisfy { $0 == "_" } || condensed.allSatisfy { $0 == "-" }
    }

    private static func isReferenceDefinition(_ line: String) -> Bool {
        line.range(of: "^\\[[^\\]]+\\]:\\s*\\S+", options: .regularExpression) != nil
    }

    /// Returns the item's text with its bullet or number removed, or nil when
    /// the line isn't a list item.
    private static func listItemBody(_ line: String) -> String? {
        if let match = line.range(of: "^[-*+]\\s+", options: .regularExpression) {
            return String(line[match.upperBound...])
        }
        if let match = line.range(of: "^\\d+[.)]\\s+", options: .regularExpression) {
            return String(line[match.upperBound...])
        }
        return nil
    }

    /// Table rows become "cell, cell, cell"; the `|---|:--:|` separator row is
    /// dropped. Speaking the pipes would be nonsense either way.
    private static func tableRowBody(_ line: String) -> String? {
        guard line.hasPrefix("|") else { return nil }
        let cells = line.split(separator: "|", omittingEmptySubsequences: true).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard !cells.isEmpty else { return nil }
        let isSeparator = cells.allSatisfy { cell in
            !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" }
        }
        guard !isSeparator else { return "" }
        return inlineStripped(cells.filter { !$0.isEmpty }.joined(separator: ", "))
    }

    private static func blockquoteStripped(_ line: String) -> String {
        guard let match = line.range(of: "^>+\\s*", options: .regularExpression) else { return line }
        return String(line[match.upperBound...])
    }

    // MARK: - Inline pass

    /// Ordered rewrites; order is load-bearing. Images go before links (an image
    /// is a link with a `!`) and links before autolinks. Code spans only drop
    /// their backticks — the content stays in place, so emphasis rules that run
    /// later may still rewrite markup characters inside what was a span.
    private static let inlineRules: [(regex: NSRegularExpression, template: String)] = {
        let specs: [(String, String)] = [
            ("!\\[[^\\]]*\\]\\([^)]*\\)", ""),                          // images: drop entirely
            ("\\[([^\\]]*)\\]\\([^)]*\\)", "$1"),                       // [text](url) → text
            ("\\[([^\\]]*)\\]\\[[^\\]]*\\]", "$1"),                     // [text][ref] → text
            ("<(?:https?|mailto)[^>]*>", ""),                           // autolinks: drop
            ("`+([^`]*)`+", "$1"),                                      // `code` → code
            ("\\*\\*\\*([^*]+)\\*\\*\\*", "$1"),
            ("\\*\\*([^*]+)\\*\\*", "$1"),
            ("\\*([^*]+)\\*", "$1"),
            ("(?<![A-Za-z0-9])___([^_]+)___(?![A-Za-z0-9])", "$1"),
            ("(?<![A-Za-z0-9])__([^_]+)__(?![A-Za-z0-9])", "$1"),
            ("(?<![A-Za-z0-9])_([^_]+)_(?![A-Za-z0-9])", "$1"),         // spares snake_case identifiers
            ("~~([^~]+)~~", "$1"),
            ("<[^>]+>", ""),                                            // stray HTML tags
            ("\\\\([\\\\`*_{}\\[\\]()#+\\-.!>])", "$1"),                // unescape
        ]
        return specs.compactMap { pattern, template in
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                // Every pattern is a literal; failing to compile is a
                // programming error, not a runtime condition to tolerate.
                assertionFailure("invalid inline rule pattern: \(pattern)")
                return nil
            }
            return (regex, template)
        }
    }()

    static func inlineStripped(_ text: String) -> String {
        var result = text
        for rule in inlineRules {
            result = rule.regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: rule.template
            )
        }
        return ExtractedDocumentBuilder.normalize(result)
    }
}
