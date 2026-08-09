import XCTest
@testable import PocketCastsFileSync

final class UploadScanPlannerTests: XCTestCase {
    private func entry(_ path: String, size: Int64 = 1000, mtime: Int64 = 5000,
                       placeholder: Bool = false) -> FolderEntry {
        FolderEntry(relativePath: path, sizeBytes: size, mtimeMs: mtime,
                    isDirectory: false, isPlaceholder: placeholder)
    }

    private func known(_ uuid: String, path: String, size: Int64 = 1000, mtime: Int64 = 5000,
                       hash: String? = nil) -> UploadScanPlanner.KnownEpisode {
        UploadScanPlanner.KnownEpisode(uuid: uuid, relativePath: path, sizeBytes: size,
                                       mtimeMs: mtime, contentHash: hash, isCanonical: hash != nil)
    }

    // MARK: Discovery

    func testUnknownFileCreatesProvisionalEpisode() {
        let actions = UploadScanPlanner.plan(
            mediaEntries: [entry("lecture.mp3")], knownEpisodes: [])
        XCTAssertEqual(actions, [.createProvisional(entry: entry("lecture.mp3"), group: "")])
    }

    func testSubfolderBecomesGroup() {
        let actions = UploadScanPlanner.plan(
            mediaEntries: [entry("Audiobooks/chapter01.mp3")], knownEpisodes: [])
        XCTAssertEqual(actions, [.createProvisional(entry: entry("Audiobooks/chapter01.mp3"), group: "Audiobooks")])
    }

    // MARK: Steady state / changes

    func testKnownUnchangedFileIsNoop() {
        let actions = UploadScanPlanner.plan(
            mediaEntries: [entry("lecture.mp3")],
            knownEpisodes: [known("ue-1", path: "lecture.mp3")])
        XCTAssertTrue(actions.isEmpty)
    }

    func testMtimeDriftAloneIsNoop() {
        // Providers rewrite mtimes during propagation; size is the signal.
        let actions = UploadScanPlanner.plan(
            mediaEntries: [entry("lecture.mp3", mtime: 999_999)],
            knownEpisodes: [known("ue-1", path: "lecture.mp3", mtime: 5000)])
        XCTAssertTrue(actions.isEmpty)
    }

    func testInPlaceContentChangeResetsIdentity() {
        let actions = UploadScanPlanner.plan(
            mediaEntries: [entry("lecture.mp3", size: 2222)],
            knownEpisodes: [known("ue-1", path: "lecture.mp3", size: 1000, hash: "old-hash")])
        XCTAssertEqual(actions, [.resetIdentity(episodeUuid: "ue-1", entry: entry("lecture.mp3", size: 2222))])
    }

    // MARK: Rename / removal

    func testRenameIsDetectedBySizeAndMtime() {
        let moved = entry("Audiobooks/renamed.mp3", size: 1234, mtime: 777)
        let actions = UploadScanPlanner.plan(
            mediaEntries: [moved],
            knownEpisodes: [known("ue-1", path: "old-name.mp3", size: 1234, mtime: 777)])
        XCTAssertEqual(actions, [.updatePath(episodeUuid: "ue-1", entry: moved, group: "Audiobooks")])
    }

    func testSizeAloneDoesNotTransferEpisodeIdentity() {
        let moved = entry("renamed.mp3", size: 1234, mtime: 777)
        let actions = UploadScanPlanner.plan(
            mediaEntries: [moved],
            knownEpisodes: [known("ue-1", path: "old-name.mp3", size: 1234, mtime: 0)])
        XCTAssertEqual(actions, [
            .createProvisional(entry: moved, group: ""),
            .removeEpisode(episodeUuid: "ue-1"),
        ])
    }

    func testDeletedFileRemovesEpisode() {
        let actions = UploadScanPlanner.plan(
            mediaEntries: [],
            knownEpisodes: [known("ue-1", path: "gone.mp3")])
        XCTAssertEqual(actions, [.removeEpisode(episodeUuid: "ue-1")])
    }

    func testIncompleteListingRetainsMissingEpisode() {
        let actions = UploadScanPlanner.plan(
            mediaEntries: [],
            knownEpisodes: [known("ue-1", path: "temporarily-missing.mp3")],
            listingIsComplete: false)
        XCTAssertTrue(actions.isEmpty)
    }

    func testIncompleteListingDoesNotInferRenameFromAbsence() {
        let listed = entry("new.mp3", size: 1000)
        let actions = UploadScanPlanner.plan(
            mediaEntries: [listed],
            knownEpisodes: [known("ue-1", path: "temporarily-missing.mp3", size: 1000, mtime: 0)],
            listingIsComplete: false)
        XCTAssertEqual(actions, [.createProvisional(entry: listed, group: "")])
    }

    func testRenameIsNotAlsoARemoval() {
        let moved = entry("new.mp3", size: 1234, mtime: 777)
        let actions = UploadScanPlanner.plan(
            mediaEntries: [moved],
            knownEpisodes: [known("ue-1", path: "old.mp3", size: 1234, mtime: 777)])
        XCTAssertFalse(actions.contains(.removeEpisode(episodeUuid: "ue-1")),
                       "a rename-claimed episode must not be removed")
        XCTAssertEqual(actions.count, 1)
    }

    // MARK: Hash resolution

    func testFreshHashPromotes() {
        let resolution = UploadScanPlanner.resolveHash(
            "new-hash", for: "ue-1", currentHash: nil, hashOwners: [:])
        XCTAssertEqual(resolution, .promote(episodeUuid: "ue-1"))
    }

    func testMatchingHashIsUnchanged() {
        let resolution = UploadScanPlanner.resolveHash(
            "same", for: "ue-1", currentHash: "same", hashOwners: ["same": "ue-1"])
        XCTAssertEqual(resolution, .unchanged)
    }

    func testKnownHashRekeysOntoCanonicalEpisode() {
        // The provisional row hashed to content another episode already
        // owns (rename detected late, or duplicate copy): merge them.
        let resolution = UploadScanPlanner.resolveHash(
            "shared-hash", for: "ue-provisional", currentHash: nil,
            hashOwners: ["shared-hash": "ue-canonical"])
        XCTAssertEqual(resolution, .rekey(provisionalUuid: "ue-provisional", canonicalUuid: "ue-canonical"))
    }
}
