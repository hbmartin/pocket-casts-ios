import PocketCastsDataModel
import XCTest

@testable import podcasts

final class UploadedGroupsBuilderTests: XCTestCase {
    private func makeEpisode(uuid: String, group: String? = nil) -> UserEpisode {
        var episode = UserEpisode()
        episode.uuid = uuid
        episode.title = uuid
        episode.groupName = group
        return episode
    }

    /// The Files table hangs its storage header off the root section, so the
    /// root group must exist even with no uploads at all.
    func testEmptyInputStillYieldsRootSection() {
        let groups = UploadedGroupsBuilder.groups(from: [])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].group, "")
        XCTAssertTrue(groups[0].episodes.isEmpty)
    }

    func testRootOnlyInputPreservesOrder() {
        let episodes = [makeEpisode(uuid: "b"), makeEpisode(uuid: "a"), makeEpisode(uuid: "c")]

        let groups = UploadedGroupsBuilder.groups(from: episodes)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].group, "")
        XCTAssertEqual(groups[0].episodes.map(\.uuid), ["b", "a", "c"])
    }

    /// When every upload sits in a named subfolder, an empty root section is
    /// still prepended so the storage header keeps its section.
    func testNamedOnlyInputPrependsEmptyRoot() {
        let episodes = [makeEpisode(uuid: "1", group: "Beta"), makeEpisode(uuid: "2", group: "alpha")]

        let groups = UploadedGroupsBuilder.groups(from: episodes)

        XCTAssertEqual(groups.map(\.group), ["", "alpha", "Beta"])
        XCTAssertTrue(groups[0].episodes.isEmpty)
        XCTAssertEqual(groups[1].episodes.map(\.uuid), ["2"])
        XCTAssertEqual(groups[2].episodes.map(\.uuid), ["1"])
    }

    func testMixedInputRootFirstThenNamedAtoZ() {
        let episodes = [
            makeEpisode(uuid: "n1", group: "Zed"),
            makeEpisode(uuid: "r1"),
            makeEpisode(uuid: "n2", group: "apple"),
            makeEpisode(uuid: "r2"),
            makeEpisode(uuid: "n3", group: "Zed")
        ]

        let groups = UploadedGroupsBuilder.groups(from: episodes)

        XCTAssertEqual(groups.map(\.group), ["", "apple", "Zed"])
        XCTAssertEqual(groups[0].episodes.map(\.uuid), ["r1", "r2"])
        XCTAssertEqual(groups[1].episodes.map(\.uuid), ["n2"])
        XCTAssertEqual(groups[2].episodes.map(\.uuid), ["n1", "n3"])
    }

    func testNilGroupNameCountsAsRoot() {
        let episodes = [makeEpisode(uuid: "a", group: nil), makeEpisode(uuid: "b", group: "Books")]

        let groups = UploadedGroupsBuilder.groups(from: episodes)

        XCTAssertEqual(groups.map(\.group), ["", "Books"])
        XCTAssertEqual(groups[0].episodes.map(\.uuid), ["a"])
    }
}
