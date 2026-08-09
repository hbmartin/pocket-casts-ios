import Foundation
@testable import PocketCastsReadAloud
@testable import podcasts
import XCTest

/// Coverage for how the ~180 installed voices get narrowed to a choice someone
/// can actually make.
final class VoiceCatalogTests: XCTestCase {
    private func voice(
        _ id: String,
        language: String,
        quality: VoiceQuality = .standard,
        name: String? = nil
    ) -> SynthesisVoice {
        SynthesisVoice(id: id, name: name ?? id, language: language, quality: quality)
    }

    // MARK: - Language matching

    /// `NLLanguageRecognizer` reports a language, not a region, so an English
    /// document has to surface en-GB and en-AU voices too — matching the full
    /// tag would leave the list empty for most documents.
    func testMatchingIsByLanguageNotRegion() {
        let catalog = VoiceCatalog(voices: [
            voice("us", language: "en-US"),
            voice("gb", language: "en-GB"),
            voice("fr", language: "fr-FR"),
        ])

        XCTAssertEqual(Set(catalog.voices(matching: "en").map(\.id)), ["us", "gb"])
        XCTAssertEqual(catalog.voices(matching: "en-AU").map(\.id).sorted(), ["gb", "us"])
        XCTAssertEqual(catalog.voices(matching: "fr").map(\.id), ["fr"])
    }

    func testUnderscoreLocaleIdentifiersMatch() {
        let catalog = VoiceCatalog(voices: [voice("us", language: "en-US")])

        XCTAssertEqual(catalog.voices(matching: "en_US").map(\.id), ["us"])
    }

    func testNoLanguageMatchesNothing() {
        let catalog = VoiceCatalog(voices: [voice("us", language: "en-US")])

        XCTAssertTrue(catalog.voices(matching: nil).isEmpty)
        XCTAssertTrue(catalog.voices(matching: "").isEmpty)
    }

    // MARK: - Ordering

    /// Compact voices sound robotic, so the good ones have to come first —
    /// nobody arrives at this screen wanting the worse option.
    func testBetterQualityIsListedFirst() {
        let catalog = VoiceCatalog(voices: [
            voice("compact", language: "en-US", quality: .standard),
            voice("premium", language: "en-US", quality: .premium),
            voice("enhanced", language: "en-US", quality: .enhanced),
        ])

        XCTAssertEqual(catalog.voices(matching: "en").map(\.id), ["premium", "enhanced", "compact"])
    }

    func testEqualQualitySortsByName() {
        let catalog = VoiceCatalog(voices: [
            voice("b", language: "en-US", name: "Bella"),
            voice("a", language: "en-US", name: "Ava"),
        ])

        XCTAssertEqual(catalog.voices(matching: "en").map(\.id), ["a", "b"])
    }

    // MARK: - Default selection

    func testPreferredVoiceIsTheBestForTheDocumentLanguage() {
        let catalog = VoiceCatalog(voices: [
            voice("en-compact", language: "en-US", quality: .standard),
            voice("fr-premium", language: "fr-FR", quality: .premium),
            voice("en-enhanced", language: "en-US", quality: .enhanced),
        ])

        XCTAssertEqual(catalog.preferredVoice(for: "en", deviceLanguage: "fr-FR")?.id, "en-enhanced")
    }

    /// The document's language wins over the device's, but a document in a
    /// language with no installed voice still has to get something.
    func testPreferredVoiceFallsBackToTheDeviceLanguage() {
        let catalog = VoiceCatalog(voices: [
            voice("en", language: "en-US"),
            voice("de", language: "de-DE"),
        ])

        XCTAssertEqual(catalog.preferredVoice(for: "ja", deviceLanguage: "de-DE")?.id, "de")
    }

    func testPreferredVoiceFallsBackToAnythingInstalled() {
        let catalog = VoiceCatalog(voices: [
            voice("only-compact", language: "sv-SE", quality: .standard),
            voice("only-premium", language: "sv-SE", quality: .premium),
        ])

        XCTAssertEqual(catalog.preferredVoice(for: "ja", deviceLanguage: "ko-KR")?.id, "only-premium")
    }

    func testPreferredVoiceIsNilWithNoVoicesAtAll() {
        XCTAssertNil(VoiceCatalog(voices: []).preferredVoice(for: "en"))
    }

    func testMultilingualProviderVoiceMatchesEveryDocumentLanguage() {
        let catalog = VoiceCatalog(voices: [
            voice("provider", language: "mul", quality: .premium),
        ])

        XCTAssertEqual(catalog.voices(matching: "fr").map(\.id), ["provider"])
        XCTAssertEqual(catalog.voices(matching: "ja-JP").map(\.id), ["provider"])
        XCTAssertEqual(VoiceCatalog.displayName(forLanguage: "mul"), L10n.readAloudAllLanguages)
    }

    // MARK: - Stored selections

    /// Voices can be deleted in iOS Settings at any time, so a stored default
    /// has to be allowed to resolve to nothing.
    func testAStoredVoiceThatIsGoneResolvesToNil() {
        let catalog = VoiceCatalog(voices: [voice("installed", language: "en-US")])

        XCTAssertEqual(catalog.voice(id: "installed")?.id, "installed")
        XCTAssertNil(catalog.voice(id: "uninstalled"))
        XCTAssertNil(catalog.voice(id: nil))
    }

    func testStoredDefaultIsIgnoredWhenItDoesNotMatchTheDocumentLanguage() {
        let catalog = VoiceCatalog(voices: [
            voice("english", language: "en-US", quality: .premium),
            voice("french", language: "fr-FR", quality: .enhanced),
        ])

        XCTAssertEqual(
            catalog.preferredVoice(storedId: "english", for: "fr", deviceLanguage: "en-US")?.id,
            "french"
        )
        XCTAssertEqual(
            catalog.preferredVoice(storedId: "english", for: nil, deviceLanguage: "fr-FR")?.id,
            "english"
        )
    }

    // MARK: - Quality reporting

    func testHighQualityDetectionDrivesTheExplainer() {
        let compactOnly = VoiceCatalog(voices: [voice("c", language: "en-US", quality: .standard)])
        let withEnhanced = VoiceCatalog(voices: [
            voice("c", language: "en-US", quality: .standard),
            voice("e", language: "en-GB", quality: .enhanced),
        ])

        XCTAssertFalse(compactOnly.hasHighQualityVoice(for: "en"))
        XCTAssertTrue(withEnhanced.hasHighQualityVoice(for: "en"))
        XCTAssertFalse(withEnhanced.hasHighQualityVoice(for: "fr"))
    }

    // MARK: - Grouping

    func testGroupsAreByExactTagAndSortedByDisplayName() {
        let catalog = VoiceCatalog(voices: [
            voice("us", language: "en-US"),
            voice("gb", language: "en-GB"),
            voice("fr", language: "fr-FR"),
        ])

        let groups = catalog.allGroups()

        XCTAssertEqual(Set(groups.map(\.id)), ["en-US", "en-GB", "fr-FR"])
        XCTAssertEqual(groups.map(\.displayName), groups.map(\.displayName).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        XCTAssertEqual(groups.reduce(0) { $0 + $1.voices.count }, 3)
    }

    func testLanguageSubtagExtraction() {
        XCTAssertEqual(VoiceCatalog.languageSubtag("en-GB"), "en")
        XCTAssertEqual(VoiceCatalog.languageSubtag("EN_us"), "en")
        XCTAssertEqual(VoiceCatalog.languageSubtag("fr"), "fr")
        XCTAssertNil(VoiceCatalog.languageSubtag(nil))
        XCTAssertNil(VoiceCatalog.languageSubtag(""))
    }
}
