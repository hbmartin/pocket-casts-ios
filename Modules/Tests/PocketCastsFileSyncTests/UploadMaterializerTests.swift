import XCTest
@testable import PocketCastsFileSync

final class UploadMaterializerTests: XCTestCase {
    func testUploadRelativePathRejectsTraversalGroups() {
        for group in [".", "..", "../escape", "nested/group", #"nested\group"#] {
            XCTAssertThrowsError(try UploadMaterializer.uploadRelativePath(fileName: "episode.mp3", group: group)) { error in
                guard case SyncFolderError.invalidPathComponent(let rejected) = error else {
                    return XCTFail("Expected invalidPathComponent, got \(error)")
                }
                XCTAssertEqual(rejected, group)
            }
        }
    }

    func testUploadRelativePathAllowsEmptyAndPlainGroups() throws {
        XCTAssertEqual(
            try UploadMaterializer.uploadRelativePath(fileName: "episode.mp3", group: nil),
            "episode.mp3")
        XCTAssertEqual(
            try UploadMaterializer.uploadRelativePath(fileName: "episode.mp3", group: ""),
            "episode.mp3")
        XCTAssertEqual(
            try UploadMaterializer.uploadRelativePath(fileName: "episode.mp3", group: "Audiobooks"),
            "Audiobooks/episode.mp3")
    }
}
