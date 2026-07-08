import XCTest
@testable import PocketCastsFileSync

final class FolderScannerTests: XCTestCase {
    private func entry(_ path: String, size: Int64 = 100, mtime: Int64 = 1000,
                       directory: Bool = false, placeholder: Bool = false) -> FolderEntry {
        FolderEntry(relativePath: path, sizeBytes: size, mtimeMs: mtime,
                    isDirectory: directory, isPlaceholder: placeholder)
    }

    func testDiffDetectsAddedModifiedRemoved() {
        let previous = [
            entry("Uploads/a.mp3"),
            entry("Uploads/b.mp3", size: 200),
            entry("Uploads/c.mp3"),
        ]
        let current = [
            entry("Uploads/a.mp3"),                       // unchanged
            entry("Uploads/b.mp3", size: 250, mtime: 2000), // modified
            entry("Uploads/d.mp3"),                       // added
        ]
        let diff = FolderScanner.diff(previous: previous, current: current)

        XCTAssertEqual(diff.added.map(\.relativePath), ["Uploads/d.mp3"])
        XCTAssertEqual(diff.modified.map(\.relativePath), ["Uploads/b.mp3"])
        XCTAssertEqual(diff.removed.map(\.relativePath), ["Uploads/c.mp3"])
    }

    func testPlaceholderMaterializationCountsAsModification() {
        let previous = [entry("Uploads/a.mp3", placeholder: true)]
        let current = [entry("Uploads/a.mp3", placeholder: false)]
        let diff = FolderScanner.diff(previous: previous, current: current)
        XCTAssertEqual(diff.modified.map(\.relativePath), ["Uploads/a.mp3"])
    }

    func testIdenticalListingsAreEmptyDiff() {
        let listing = [entry("a.mp3"), entry("dir", directory: true)]
        XCTAssertTrue(FolderScanner.diff(previous: listing, current: listing).isEmpty)
    }

    func testDuplicatePreviousPathsDoNotCrashDiff() {
        let previous = [
            entry("Uploads/a.mp3", size: 100),
            entry("Uploads/a.mp3", size: 200),
        ]
        let current = [entry("Uploads/a.mp3", size: 200)]

        XCTAssertTrue(FolderScanner.diff(previous: previous, current: current).isEmpty)
    }

    func testMediaFilesFiltersDirectoriesHiddenAndUnsupported() {
        let entries = [
            entry("Uploads/lecture.mp3"),
            entry("Uploads/Audiobooks", directory: true),
            entry("Uploads/.hidden.mp3"),
            entry("Uploads/notes.txt"),
            entry("Uploads/Audiobooks/chapter1.m4b"),
        ]
        let supported: Set<String> = ["mp3", "m4b"]
        let media = FolderScanner.mediaFiles(in: entries) { name in
            supported.contains((name as NSString).pathExtension.lowercased())
        }
        XCTAssertEqual(media.map(\.relativePath),
                       ["Uploads/lecture.mp3", "Uploads/Audiobooks/chapter1.m4b"])
    }
}
