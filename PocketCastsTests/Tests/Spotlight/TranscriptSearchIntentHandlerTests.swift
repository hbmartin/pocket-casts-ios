import Foundation
import PocketCastsDataModel
import XCTest

@testable import podcasts

nonisolated private struct FakeFacade: TranscriptSearchFacade {
    var hits: [TranscriptSearchHit] = []
    var titles: [String: String] = [:]

    func search(term: String, limit: Int) -> [TranscriptSearchHit] {
        Array(hits.prefix(limit))
    }

    func episodeTitle(episodeUuid: String) -> String? {
        titles[episodeUuid]
    }

    func hit(episodeUuid: String, segmentIndex: Int) -> TranscriptSearchHit? {
        hits.first { $0.episodeUuid == episodeUuid && $0.segmentIndex == segmentIndex }
    }
}

final class TranscriptSearchIntentHandlerTests: XCTestCase {

    private func makeHit(episode: String, segment: Int, snippet: String, startTime: TimeInterval = 30) -> TranscriptSearchHit {
        TranscriptSearchHit(
            episodeUuid: episode,
            podcastUuid: "pod-1",
            segmentIndex: segment,
            startTime: startTime,
            endTime: nil,
            speaker: nil,
            source: .generated,
            snippet: snippet
        )
    }

    func testTopHitsPreserveOrderStripMarkersAndDropUnresolvableEpisodes() {
        let facade = FakeFacade(
            hits: [
                makeHit(episode: "ep-1", segment: 3, snippet: "about <b>climate</b> change"),
                makeHit(episode: "ep-ghost", segment: 0, snippet: "gone"),
                makeHit(episode: "ep-2", segment: 7, snippet: "more <b>climate</b>")
            ],
            titles: ["ep-1": "Episode One", "ep-2": "Episode Two"]
        )
        let entities = TranscriptSearchIntentHandler(facade: facade).topHits(for: "climate")

        XCTAssertEqual(entities.map(\.id), ["ep-1:3", "ep-2:7"], "BM25 order kept; unresolvable episode dropped")
        XCTAssertEqual(entities.first?.episodeTitle, "Episode One")
        XCTAssertEqual(entities.first?.snippet, "about climate change")
    }

    func testEntityForIdReResolvesAcrossRestarts() {
        let facade = FakeFacade(
            hits: [makeHit(episode: "ep-1", segment: 3, snippet: "plain text", startTime: 754)],
            titles: ["ep-1": "Episode One"]
        )
        let handler = TranscriptSearchIntentHandler(facade: facade)

        let entity = handler.entity(forId: "ep-1:3")
        XCTAssertEqual(entity?.episodeUuid, "ep-1")
        XCTAssertEqual(entity?.segmentIndex, 3)
        XCTAssertEqual(entity?.startTime, 754)

        XCTAssertNil(handler.entity(forId: "ep-1:99"), "segment no longer indexed")
        XCTAssertNil(handler.entity(forId: "junk"))
        XCTAssertNil(handler.entity(forId: "ep-1:notanumber"))
    }

    func testTimeString() {
        XCTAssertEqual(TranscriptSearchIntentHandler.timeString(0), "0:00")
        XCTAssertEqual(TranscriptSearchIntentHandler.timeString(754), "12:34")
        XCTAssertEqual(TranscriptSearchIntentHandler.timeString(3725), "1:02:05")
        XCTAssertEqual(TranscriptSearchIntentHandler.timeString(-5), "0:00")
    }

    func testPlainSnippetStripsAllMarkers() {
        XCTAssertEqual(
            TranscriptSearchIntentHandler.plainSnippet("<b>a</b> and <b>b</b>"),
            "a and b"
        )
    }
}
