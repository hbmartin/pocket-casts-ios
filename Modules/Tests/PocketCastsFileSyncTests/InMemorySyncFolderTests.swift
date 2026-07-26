import XCTest
@testable import PocketCastsFileSync

final class InMemorySyncFolderTests: XCTestCase {
    func testListIncludesEmptyExplicitDirectoryWithinBoundary() async throws {
        let folder = InMemorySyncFolder()
        try await folder.createDirectory("Uploads/Empty")
        try await folder.createDirectory("Other/Excluded")

        let entries = try await folder.list("Uploads")

        XCTAssertEqual(entries.map(\.relativePath), ["Uploads/Empty"])
        XCTAssertTrue(entries.allSatisfy(\.isDirectory))
    }

    func testListIncludesExplicitAndFileDerivedNestedDirectoriesWithinBoundary() async throws {
        let folder = InMemorySyncFolder()
        try await folder.createDirectory("Uploads/Explicit/Nested")
        try await folder.coordinatedWrite("Uploads/From File/Deep/episode.mp3", data: Data([1]))
        try await folder.coordinatedWrite("Outside/ignored.mp3", data: Data([2]))

        let paths = try await folder.list("Uploads").map(\.relativePath)

        XCTAssertEqual(paths, [
            "Uploads/Explicit/Nested",
            "Uploads/From File",
            "Uploads/From File/Deep",
            "Uploads/From File/Deep/episode.mp3",
        ])
    }
}
