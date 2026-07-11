import Foundation
@testable import PocketCastsServer
import XCTest

final class ShowInfoDataRetrieverTests: XCTestCase {
    func testLocallySeededShowInfoIsSharedAcrossRetrieverInstances() async throws {
        let podcastUuid = UUID().uuidString
        let episodeUuid = UUID().uuidString
        let showInfo = try JSONSerialization.data(withJSONObject: [
            "podcast": [
                "episodes": [[
                    "uuid": episodeUuid,
                    "title": "Locally seeded episode",
                ]],
            ],
        ])
        let seeder = ShowInfoDataRetriever()
        let reader = ShowInfoDataRetriever()

        await seeder.storeLocalShowInfo(data: showInfo, for: podcastUuid)
        let metadata = try await reader.loadEpisodeDataFromCache(
            for: podcastUuid,
            episodeUuid: episodeUuid,
            useCacheOnly: true
        )

        let metadataData = try XCTUnwrap(metadata?.data(using: .utf8))
        let decoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: metadataData) as? [String: String]
        )
        XCTAssertEqual(decoded["uuid"], episodeUuid)
        XCTAssertEqual(decoded["title"], "Locally seeded episode")
    }
}
