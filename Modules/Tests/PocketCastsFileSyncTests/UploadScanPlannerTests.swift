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

    private func identity(_ uuid: String, path: String, size: Int64 = 1000,
                          sha256: String = "hash-1") -> Filesync_UploadIdentity {
        var identity = Filesync_UploadIdentity()
        identity.uuid = uuid
        identity.relativePath = path
        identity.sizeBytes = size
        identity.sha256 = sha256
        return identity
    }

    // MARK: Discovery

    func testUnknownFileCreatesProvisionalEpisode() {
        let actions = UploadScanPlanner.plan(
            mediaEntries: [entry("lecture.mp3")], knownEpisodes: [], manifest: [])
        XCTAssertEqual(actions, [.createProvisional(entry: entry("lecture.mp3"), group: "")])
    }

    func testSubfolderBecomesGroup() {
        let actions = UploadScanPlanner.plan(
            mediaEntries: [entry("Audiobooks/chapter01.mp3")], knownEpisodes: [], manifest: [])
        XCTAssertEqual(actions, [.createProvisional(entry: entry("Audiobooks/chapter01.mp3"), group: "Audiobooks")])
    }

    func testManifestIdentityIsAdoptedWithoutDownloading() {
        // Device A published this file's identity; device B sees a
        // placeholder with matching path+size and adopts the shared uuid.
        let published = identity("ue-shared", path: "book.m4b", size: 9999)
        let actions = UploadScanPlanner.plan(
            mediaEntries: [entry("book.m4b", size: 9999, placeholder: true)],
            knownEpisodes: [], manifest: [published])
        XCTAssertEqual(actions, [.adoptIdentity(entry: entry("book.m4b", size: 9999, placeholder: true),
                                                identity: published)])
    }

    func testManifestPathWithDifferentSizeIsNotAdopted() {
        // Same path but the bytes differ: the file was replaced. It must
        // become a new provisional episode, not adopt the stale identity.
        let published = identity("ue-old", path: "notes.mp3", size: 111)
        let actions = UploadScanPlanner.plan(
            mediaEntries: [entry("notes.mp3", size: 222)],
            knownEpisodes: [], manifest: [published])
        XCTAssertEqual(actions, [.createProvisional(entry: entry("notes.mp3", size: 222), group: "")])
    }

    // MARK: Steady state / changes

    func testKnownUnchangedFileIsNoop() {
        let actions = UploadScanPlanner.plan(
            mediaEntries: [entry("lecture.mp3")],
            knownEpisodes: [known("ue-1", path: "lecture.mp3")],
            manifest: [])
        XCTAssertTrue(actions.isEmpty)
    }

    func testMtimeDriftAloneIsNoop() {
        // Providers rewrite mtimes during propagation; size is the signal.
        let actions = UploadScanPlanner.plan(
            mediaEntries: [entry("lecture.mp3", mtime: 999_999)],
            knownEpisodes: [known("ue-1", path: "lecture.mp3", mtime: 5000)],
            manifest: [])
        XCTAssertTrue(actions.isEmpty)
    }

    func testInPlaceContentChangeResetsIdentity() {
        let actions = UploadScanPlanner.plan(
            mediaEntries: [entry("lecture.mp3", size: 2222)],
            knownEpisodes: [known("ue-1", path: "lecture.mp3", size: 1000, hash: "old-hash")],
            manifest: [])
        XCTAssertEqual(actions, [.resetIdentity(episodeUuid: "ue-1", entry: entry("lecture.mp3", size: 2222))])
    }

    // MARK: Rename / removal

    func testRenameIsDetectedBySizeAndMtime() {
        let moved = entry("Audiobooks/renamed.mp3", size: 1234, mtime: 777)
        let actions = UploadScanPlanner.plan(
            mediaEntries: [moved],
            knownEpisodes: [known("ue-1", path: "old-name.mp3", size: 1234, mtime: 777)],
            manifest: [])
        XCTAssertEqual(actions, [.updatePath(episodeUuid: "ue-1", entry: moved, group: "Audiobooks")])
    }

    func testDeletedFileRemovesEpisode() {
        let actions = UploadScanPlanner.plan(
            mediaEntries: [],
            knownEpisodes: [known("ue-1", path: "gone.mp3")],
            manifest: [])
        XCTAssertEqual(actions, [.removeEpisode(episodeUuid: "ue-1")])
    }

    func testRenameIsNotAlsoARemoval() {
        let moved = entry("new.mp3", size: 1234, mtime: 777)
        let actions = UploadScanPlanner.plan(
            mediaEntries: [moved],
            knownEpisodes: [known("ue-1", path: "old.mp3", size: 1234, mtime: 777)],
            manifest: [])
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
