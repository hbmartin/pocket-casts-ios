import Foundation
import PocketCastsReadAloud

/// Organises the installed voices into something a picker can show.
///
/// A modern device offers on the order of 180 voices across ~50 languages, so a
/// flat list is unusable. The document's detected language is the one strong
/// signal available, and everything here exists to put it to work.
nonisolated struct VoiceCatalog: Sendable {
    struct LanguageGroup: Identifiable, Sendable {
        /// BCP-47 tag, e.g. "en-GB".
        let id: String
        /// Localized for display, e.g. "English (United Kingdom)".
        let displayName: String
        let voices: [SynthesisVoice]
    }

    let voices: [SynthesisVoice]

    init(voices: [SynthesisVoice]) {
        self.voices = voices
    }

    // MARK: - Grouping

    /// Voices whose language matches `language`, best quality first.
    ///
    /// Matches on the language subtag rather than the whole tag, so a document
    /// detected as "en" surfaces en-US, en-GB and en-AU voices together —
    /// `NLLanguageRecognizer` reports a language, not a region, and someone
    /// reading an English document is not served by an empty list.
    func voices(matching language: String?) -> [SynthesisVoice] {
        guard let subtag = Self.languageSubtag(language) else { return [] }
        return voices
            .filter { Self.languageSubtag($0.language) == subtag }
            .sorted(by: Self.betterFirst)
    }

    /// Every voice, grouped by exact language tag, groups A–Z.
    func allGroups() -> [LanguageGroup] {
        Dictionary(grouping: voices, by: \.language)
            .map { language, voices in
                LanguageGroup(
                    id: language,
                    displayName: Self.displayName(forLanguage: language),
                    voices: voices.sorted(by: Self.betterFirst)
                )
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    // MARK: - Defaults

    /// The voice to preselect: the best one for the document's language, falling
    /// back to the device's language, then to anything at all.
    ///
    /// Quality-first because the difference between a compact and an enhanced
    /// voice is the difference between a robot and something listenable, and
    /// nobody arrives at this screen wanting the worse option.
    func preferredVoice(for language: String?, deviceLanguage: String = Locale.current.identifier) -> SynthesisVoice? {
        voices(matching: language).first
            ?? voices(matching: deviceLanguage).first
            ?? voices.min(by: Self.betterFirst)
    }

    /// Resolves a stored voice id, or nil when that voice is no longer installed
    /// (the user can delete voices in iOS Settings at any time).
    func voice(id: String?) -> SynthesisVoice? {
        guard let id else { return nil }
        return voices.first { $0.id == id }
    }

    /// Whether anything better than a compact voice is installed for a language.
    /// Drives nothing functional — it is what the "you can download better
    /// voices" explainer keys off when deciding how emphatic to be.
    func hasHighQualityVoice(for language: String?) -> Bool {
        voices(matching: language).contains { $0.quality > .standard }
    }

    // MARK: - Helpers

    /// "en-GB" → "en"; nil or empty → nil.
    static func languageSubtag(_ language: String?) -> String? {
        guard let language, !language.isEmpty else { return nil }
        let normalized = language.replacingOccurrences(of: "_", with: "-")
        let subtag = normalized.split(separator: "-").first.map(String.init) ?? normalized
        return subtag.isEmpty ? nil : subtag.lowercased()
    }

    static func displayName(forLanguage language: String) -> String {
        Locale.current.localizedString(forIdentifier: language)
            ?? Locale.current.localizedString(forIdentifier: language.replacingOccurrences(of: "-", with: "_"))
            ?? language
    }

    private static func betterFirst(_ lhs: SynthesisVoice, _ rhs: SynthesisVoice) -> Bool {
        if lhs.quality != rhs.quality { return lhs.quality > rhs.quality }
        if lhs.language != rhs.language { return lhs.language < rhs.language }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
