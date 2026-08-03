import Foundation

public extension String {
    /// THE canonical entity-name folding (Highlights S10, ADR-0017): the one
    /// rule every person/book identity key uses — transcript mentions, feed
    /// credits, renamed speakers, and the backend's person aliases must all
    /// agree, or the same human splits into several entities.
    ///
    /// Trim → case fold → diacritic fold → collapse inner whitespace.
    var foldedEntityKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
