import Foundation
import Testing
@testable import PocketCastsDataModel

/// Decode coverage for `Episode.Metadata` (plans/AI UX Improvements.md
/// Phase 6): the `persons` credits array and the chapter `url`/`href`/`image`
/// fields, plus the regression guarantee that payloads without any of them
/// keep decoding exactly as before. Uses the same snake_case strategy as
/// `ShowInfoCoordinator`.
@Suite("Episode.Metadata decoding")
struct EpisodeMetadataDecodeTests {
    private func decode(_ json: String) throws -> Episode.Metadata {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Episode.Metadata.self, from: Data(json.utf8))
    }

    @Test("payloads without persons or chapter link fields decode unchanged")
    func decodesLegacyPayload() throws {
        let metadata = try decode("""
        {
            "show_notes": "<p>Notes</p>",
            "image": "https://example.com/art.jpg",
            "chapters": [{"start_time": 0, "title": "Intro", "end_time": 60}],
            "chapters_url": "https://example.com/chapters.json",
            "transcripts": [{"url": "https://example.com/t.vtt", "type": "text/vtt"}]
        }
        """)

        #expect(metadata.showNotes == "<p>Notes</p>")
        #expect(metadata.persons == nil)

        let chapter = try #require(metadata.chapters?.first)
        #expect(chapter.startTime == 0)
        #expect(chapter.title == "Intro")
        #expect(chapter.endTime == 60)
        #expect(chapter.url == nil)
        #expect(chapter.image == nil)
    }

    @Test("chapter decode reads url, accepts href as an alias, and prefers url when both are present")
    func decodesChapterLinks() throws {
        let metadata = try decode("""
        {
            "chapters": [
                {"start_time": 0, "title": "Url", "url": "https://example.com/a"},
                {"start_time": 60, "title": "Href alias", "href": "https://example.com/b"},
                {"start_time": 120, "title": "Both", "url": "https://example.com/url-wins", "href": "https://example.com/loser"},
                {"start_time": 180, "title": "Image", "image": "https://example.com/chapter.jpg"}
            ],
            "transcripts": []
        }
        """)

        let chapters = try #require(metadata.chapters)
        #expect(chapters.count == 4)
        #expect(chapters[0].url == "https://example.com/a")
        #expect(chapters[1].url == "https://example.com/b")
        #expect(chapters[2].url == "https://example.com/url-wins")
        #expect(chapters[3].url == nil)
        #expect(chapters[3].image == "https://example.com/chapter.jpg")
    }

    @Test("persons decode with full and minimal entries")
    func decodesPersons() throws {
        let metadata = try decode("""
        {
            "persons": [
                {"name": "Jane Host", "role": "host", "group": "cast", "img": "https://example.com/jane.jpg", "href": "https://example.com/jane"},
                {"name": "Plain Name"}
            ],
            "transcripts": []
        }
        """)

        let persons = try #require(metadata.persons)
        #expect(persons.count == 2)

        let jane = try #require(persons.first)
        #expect(jane.name == "Jane Host")
        #expect(jane.role == "host")
        #expect(jane.group == "cast")
        #expect(jane.img == "https://example.com/jane.jpg")
        #expect(jane.href == "https://example.com/jane")

        let plain = try #require(persons.last)
        #expect(plain.name == "Plain Name")
        #expect(plain.role == nil)
        #expect(plain.group == nil)
        #expect(plain.img == nil)
        #expect(plain.href == nil)
    }

    @Test("an empty persons array decodes as empty, not nil")
    func decodesEmptyPersons() throws {
        let metadata = try decode("""
        {"persons": [], "transcripts": []}
        """)

        #expect(metadata.persons?.isEmpty == true)
    }
}
