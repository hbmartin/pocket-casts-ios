import Foundation
@testable import PocketCastsDataModel
@testable import PocketCastsReadAloud
@testable import podcasts
import XCTest

/// Coverage for the one production function the first end-to-end pass could not
/// reach: `UIDocumentPickerViewController` runs out-of-process, so the picker →
/// import handoff was undrivable and `commit` went unexercised. The compose
/// screen gives it a second caller, and these give it a first test.
final class NarrationImporterTests: DBTestCase {
    private var storage: ReadAloudStorage!
    private var root: URL!
    private var importer: NarrationImporter!
    private var createdDocumentUuids: [String] = []

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImporterTests-\(UUID().uuidString)", isDirectory: true)
        storage = ReadAloudStorage(rootURL: root)
        importer = NarrationImporter(dataManager: dataManager, storage: storage)
    }

    override func tearDown() async throws {
        for uuid in createdDocumentUuids {
            dataManager.readAloud.deleteDocument(uuid: uuid)
        }
        createdDocumentUuids = []
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    private func voice() -> SynthesisVoice {
        SynthesisVoice(id: "test.voice", name: "Test Voice", language: "en-US")
    }

    private func track(_ document: ReadAloudDocumentRecord) {
        createdDocumentUuids.append(document.uuid)
    }

    private func sourceFileCount() throws -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: storage.sourcesURL.path).count) ?? 0
    }

    // MARK: - Composed text

    func testCommitWritesDocumentNarrationAndSource() throws {
        let preview = try importer.preview(text: "First sentence. Second sentence.", title: "My Note")

        let created = try importer.commit(
            preview: preview, title: "My Note", engine: .appleBuiltIn, providerId: nil, modelId: nil, voice: voice()
        )
        track(created.document)

        let document = try XCTUnwrap(dataManager.readAloud.document(uuid: created.document.uuid))
        XCTAssertEqual(document.title, "My Note")
        XCTAssertEqual(document.source, .composed)
        XCTAssertGreaterThan(document.characterCount, 0)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: storage.sourceURL(relativePath: document.sourcePath).path),
            "the source document was not retained"
        )

        let narrations = dataManager.readAloud.narrations(documentUuid: document.uuid)
        XCTAssertEqual(narrations.count, 1)
        XCTAssertEqual(narrations.first?.voiceId, "test.voice")
        XCTAssertEqual(narrations.first?.narrationState, .queued)
        XCTAssertEqual(narrations.first?.documentUuid, document.uuid)
    }

    /// The retained copy has to be the text, not a path that happens to exist.
    func testTheRetainedSourceContainsTheComposedText() throws {
        let text = "The quick brown fox jumps over the lazy dog."
        let preview = try importer.preview(text: text, title: "Fox")

        let created = try importer.commit(
            preview: preview, title: "Fox", engine: .appleBuiltIn, providerId: nil, modelId: nil, voice: voice()
        )
        track(created.document)

        let written = try String(contentsOf: storage.sourceURL(relativePath: created.document.sourcePath), encoding: .utf8)
        XCTAssertEqual(written, text)
    }

    func testABlankTitleFallsBackToTheSuggestedOne() throws {
        let preview = try importer.preview(text: "# A Leading Heading\n\nBody text follows.", title: nil)

        let created = try importer.commit(
            preview: preview, title: "   ", engine: .appleBuiltIn, providerId: nil, modelId: nil, voice: voice()
        )
        track(created.document)

        XCTAssertEqual(created.document.title, preview.document.suggestedTitle)
        XCTAssertFalse(created.document.title.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    func testSaveDraftPersistsComposedTextWithoutStartingNarration() throws {
        let text = "Text that must survive while the voice sheet is open."
        let preview = try importer.preview(text: text, title: "Durable Draft")

        let document = try importer.saveDraft(preview: preview, title: "Durable Draft")
        track(document)

        XCTAssertEqual(dataManager.readAloud.document(uuid: document.uuid)?.title, "Durable Draft")
        XCTAssertTrue(dataManager.readAloud.narrations(documentUuid: document.uuid).isEmpty)
        XCTAssertEqual(
            try String(contentsOf: storage.sourceURL(relativePath: document.sourcePath), encoding: .utf8),
            text
        )
    }

    // MARK: - Picked files

    func testCommitCopiesAPickedFileIn() throws {
        let picked = root.appendingPathComponent("Essay.md")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "# Essay\n\nSome body text here.".write(to: picked, atomically: true, encoding: .utf8)
        let preview = try importer.preview(fileURL: picked, sourceKind: .picked)

        let created = try importer.commit(
            preview: preview, title: preview.document.suggestedTitle,
            engine: .appleBuiltIn, providerId: nil, modelId: nil, voice: voice()
        )
        track(created.document)

        XCTAssertEqual(created.document.originalFilename, "Essay.md")
        XCTAssertEqual(created.document.source, .picked)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.sourceURL(relativePath: created.document.sourcePath).path))
        // The picker hands back a temp copy that is deleted after import, so the
        // retained copy must be ours and must outlive it.
        try? FileManager.default.removeItem(at: picked)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.sourceURL(relativePath: created.document.sourcePath).path))
    }

    // MARK: - Failure

    /// A commit that cannot retain the source must write no rows at all —
    /// a document row pointing at a file that was never written would show up in
    /// the library and fail forever.
    ///
    /// Forced by making the sources *directory* path an ordinary file, so
    /// creating it fails. The DB-insert failure branch is not reachable from a
    /// test: both uuids are freshly generated inside `commit`, so nothing can
    /// collide, and `NarrationImporter` takes a concrete `DataManager` rather
    /// than a seam. That branch stays covered by inspection only.
    func testACommitThatCannotRetainTheSourceWritesNoRows() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not a directory".utf8).write(to: storage.sourcesURL)

        let preview = try importer.preview(text: "Some text to narrate.", title: "Doc")
        let documentsBefore = dataManager.readAloud.allDocuments().count

        XCTAssertThrowsError(
            try importer.commit(
                preview: preview, title: "Doc", engine: .appleBuiltIn, providerId: nil, modelId: nil, voice: voice()
            )
        )
        XCTAssertEqual(dataManager.readAloud.allDocuments().count, documentsBefore)
    }

    // MARK: - Re-narration

    /// The reason the document table exists: a second narration shares the
    /// document's single retained file rather than copying it.
    func testNarrateAgainSharesTheSourceFile() throws {
        let preview = try importer.preview(text: "Shared source text.", title: "Shared")
        let created = try importer.commit(
            preview: preview, title: "Shared", engine: .appleBuiltIn, providerId: nil, modelId: nil, voice: voice()
        )
        track(created.document)
        let afterFirst = try sourceFileCount()

        let second = try importer.narrateAgain(
            document: created.document, engine: .appleBuiltIn, providerId: nil,
            modelId: nil, voice: SynthesisVoice(id: "other.voice", name: "Other", language: "en-US")
        )

        XCTAssertEqual(try sourceFileCount(), afterFirst, "re-narration duplicated the source file")
        XCTAssertEqual(second.documentUuid, created.document.uuid)
        XCTAssertEqual(dataManager.readAloud.narrations(documentUuid: created.document.uuid).count, 2)
    }

    // MARK: - Deletion

    func testDeletingADocumentRemovesItsRetainedSource() throws {
        let preview = try importer.preview(text: "Doomed text.", title: "Doomed")
        let created = try importer.commit(
            preview: preview, title: "Doomed", engine: .appleBuiltIn, providerId: nil, modelId: nil, voice: voice()
        )
        let sourcePath = created.document.sourcePath

        importer.delete(document: created.document)

        XCTAssertNil(dataManager.readAloud.document(uuid: created.document.uuid))
        XCTAssertTrue(dataManager.readAloud.narrations(documentUuid: created.document.uuid).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.sourceURL(relativePath: sourcePath).path))
    }

    /// Deleting one narration must leave the document and its text alone.
    func testDeletingANarrationKeepsTheDocument() throws {
        let preview = try importer.preview(text: "Kept text.", title: "Kept")
        let created = try importer.commit(
            preview: preview, title: "Kept", engine: .appleBuiltIn, providerId: nil, modelId: nil, voice: voice()
        )
        track(created.document)

        importer.delete(narration: created.narration)

        XCTAssertNil(dataManager.readAloud.narration(uuid: created.narration.uuid))
        XCTAssertNotNil(dataManager.readAloud.document(uuid: created.document.uuid))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.sourceURL(relativePath: created.document.sourcePath).path))
    }
}
