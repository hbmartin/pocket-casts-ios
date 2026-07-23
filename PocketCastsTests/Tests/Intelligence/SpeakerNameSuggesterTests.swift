import XCTest

@testable import podcasts

final class SpeakerNameSuggesterTests: XCTestCase {

    // MARK: - Digest

    func testOpeningDigestFlattensVoiceTagsAndSkipsChrome() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:04.000
        <v Speaker 1>Welcome back to the show, I'm Alice.

        00:00:04.000 --> 00:00:08.000
        <v Speaker 2>Thanks for having me, Alice.

        00:00:08.000 --> 00:00:10.000
        No voice tag on this one.
        """
        let digest = SpeakerNameSuggester.openingDigest(fromVTT: vtt)

        XCTAssertEqual(digest, """
        Speaker 1: Welcome back to the show, I'm Alice.
        Speaker 2: Thanks for having me, Alice.
        No voice tag on this one.
        """)
    }

    func testOpeningDigestRespectsCharacterBudget() {
        let cue = "00:00:00.000 --> 00:00:01.000\n<v Speaker 1>" + String(repeating: "a", count: 100)
        let vtt = "WEBVTT\n\n" + Array(repeating: cue, count: 50).joined(separator: "\n\n")
        let digest = SpeakerNameSuggester.openingDigest(fromVTT: vtt, characterBudget: 300)
        XCTAssertLessThanOrEqual(digest.count, 300)
        XCTAssertTrue(digest.hasPrefix("Speaker 1: "))
    }

    func testOpeningDigestDoesNotScanPastBoundedPrefixOfSkippedChrome() {
        let skippedChrome = Array(
            repeating: "00:00:00.000 --> 00:00:01.000",
            count: 20
        ).joined(separator: "\n")
        let vtt = "WEBVTT\n\(skippedChrome)\n<v Speaker 1>This sentinel is beyond the scan window."

        let digest = SpeakerNameSuggester.openingDigest(fromVTT: vtt, characterBudget: 40)

        XCTAssertFalse(digest.contains("sentinel"))
    }

    func testOpeningDigestRejectsNonPositiveBudget() {
        XCTAssertEqual(SpeakerNameSuggester.openingDigest(fromVTT: "<v Speaker 1>Hello", characterBudget: 0), "")
    }

    func testEmptyVTTProducesEmptyDigest() {
        XCTAssertTrue(SpeakerNameSuggester.openingDigest(fromVTT: "WEBVTT\n").isEmpty)
    }

    // MARK: - Validation

    private func item(_ number: Int, _ name: String) -> GeneratedSpeakerNameItem {
        GeneratedSpeakerNameItem(speakerNumber: number, name: name)
    }

    func testValidationBoundsModelOutput() {
        let validated = SpeakerNameSuggester.validated([
            item(1, " Alice "),
            item(2, "\"Bob\""),
            item(0, "OutOfRange"),
            item(9, "AlsoOutOfRange"),
            item(3, ""),
            item(3, "12345"),
            item(3, String(repeating: "x", count: 60)),
            item(3, "Speaker 3")
        ], speakerCount: 3)

        XCTAssertEqual(validated, [1: "Alice", 2: "Bob"])
    }

    func testValidationDropsDuplicateNamesAndKeepsFirstPerSpeaker() {
        let validated = SpeakerNameSuggester.validated([
            item(1, "Alice"),
            item(2, "alice"),
            item(1, "Alicia")
        ], speakerCount: 3)

        XCTAssertEqual(validated, [1: "Alice"], "one suggestion per name and per speaker")
    }

    func testValidationRejectsExactGenericSpeakerButAllowsNamesStartingWithSpeaker() {
        let validated = SpeakerNameSuggester.validated([
            item(1, "Speaker"),
            item(2, "speaker"),
            item(3, "Speakersmith")
        ], speakerCount: 3)

        XCTAssertEqual(validated, [3: "Speakersmith"])
    }
}
