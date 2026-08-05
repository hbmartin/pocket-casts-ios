import Foundation
import PocketCastsDataModel
import PocketCastsReadAloud
import UniformTypeIdentifiers

/// Creates documents and narrations: extract the text, retain the source, write
/// the rows.
///
/// The one place a `ReadAloudDocument` is born, so every entry point — picker,
/// compose screen, share sheet, App Intent — produces identically shaped rows.
/// Rendering is `NarrationQueue`'s job; this type never speaks.
nonisolated struct NarrationImporter: Sendable {
    /// A document that has been read but not yet committed, so the import screen
    /// can show the title, size and detected language before the user commits to
    /// anything (and, for paid engines, before anything is spent).
    struct Preview: Sendable {
        let document: ExtractedDocument
        let originalFilename: String?
        let utType: UTType?
        let sourceKind: NarrationSourceKind
        /// Nil for composed text, which has no file to copy in.
        let sourceURL: URL?
        /// Set for composed text, which is written out at commit time.
        let composedText: String?
    }

    private let dataManager: DataManager
    private let storage: ReadAloudStorage
    private let extractors: TextExtractorRegistry

    init(
        dataManager: DataManager = .sharedManager,
        storage: ReadAloudStorage = .default,
        extractors: TextExtractorRegistry = .standard
    ) {
        self.dataManager = dataManager
        self.storage = storage
        self.extractors = extractors
    }

    // MARK: - Preview

    func preview(fileURL: URL, sourceKind: NarrationSourceKind) throws -> Preview {
        guard let data = try? Data(contentsOf: fileURL) else {
            throw ReadAloudError.sourceUnreadable
        }
        let filename = fileURL.lastPathComponent
        let type = UTType(filenameExtension: fileURL.pathExtension)

        return Preview(
            document: try extractors.extract(data: data, filename: filename, type: type),
            originalFilename: filename,
            utType: type,
            sourceKind: sourceKind,
            sourceURL: fileURL,
            composedText: nil
        )
    }

    func preview(text: String, title: String?) throws -> Preview {
        let document = try extractors.extract(data: Data(text.utf8), filename: title.map { "\($0).txt" }, type: .plainText)

        return Preview(
            document: document,
            originalFilename: nil,
            utType: .plainText,
            sourceKind: .composed,
            sourceURL: nil,
            composedText: text
        )
    }

    // MARK: - Commit

    /// Retains the source, then writes the document and its first narration in
    /// one transaction.
    ///
    /// Voice and engine are written onto the narration here and never mutated
    /// afterwards. That is what makes the resume checkpoint sound: rendered
    /// chunks can never disagree with the settings a later run reads back.
    /// Choosing a different voice creates another narration, never an edit.
    func commit(
        preview: Preview,
        title: String,
        engine: NarrationEngineKind,
        providerId: String?,
        voice: SynthesisVoice
    ) throws -> (document: ReadAloudDocumentRecord, narration: NarrationRecord) {
        let documentUuid = UUID().uuidString.lowercased()

        let sourcePath: String
        if let composedText = preview.composedText {
            sourcePath = try storage.writeSource(text: composedText, documentUuid: documentUuid)
        } else if let sourceURL = preview.sourceURL {
            sourcePath = try storage.importSource(from: sourceURL, documentUuid: documentUuid)
        } else {
            throw ReadAloudError.sourceUnreadable
        }

        var document = ReadAloudDocumentRecord()
        document.uuid = documentUuid
        document.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? preview.document.suggestedTitle
            : title
        document.originalFilename = preview.originalFilename
        document.source = preview.sourceKind
        document.utType = preview.utType?.identifier
        document.sourcePath = sourcePath
        document.characterCount = Int32(preview.document.characterCount)
        document.language = preview.document.detectedLanguage
        document.addedDate = Date().timeIntervalSince1970

        let narration = Self.makeNarration(
            documentUuid: documentUuid,
            engine: engine,
            providerId: providerId,
            voice: voice
        )

        guard dataManager.readAloud.add(document: document, narration: narration) else {
            storage.deleteSource(relativePath: sourcePath)
            throw ReadAloudError.engineFailure
        }
        return (document, narration)
    }

    /// Narrates an existing document again — a different voice, or a fresh
    /// attempt after deleting the episode. The source file is the document's and
    /// is shared, never copied.
    func narrateAgain(
        document: ReadAloudDocumentRecord,
        engine: NarrationEngineKind,
        providerId: String?,
        voice: SynthesisVoice
    ) throws -> NarrationRecord {
        let narration = Self.makeNarration(
            documentUuid: document.uuid,
            engine: engine,
            providerId: providerId,
            voice: voice
        )
        guard dataManager.readAloud.add(narration) else {
            throw ReadAloudError.engineFailure
        }
        return narration
    }

    private static func makeNarration(
        documentUuid: String,
        engine: NarrationEngineKind,
        providerId: String?,
        voice: SynthesisVoice
    ) -> NarrationRecord {
        var narration = NarrationRecord()
        narration.uuid = UUID().uuidString.lowercased()
        narration.documentUuid = documentUuid
        narration.engine = engine
        narration.providerId = providerId
        narration.voiceId = voice.id
        narration.voiceName = voice.name
        narration.narrationState = .queued
        narration.createdDate = Date().timeIntervalSince1970
        return narration
    }

    // MARK: - Deletion

    /// Deletes one narration and the episode it produced, leaving the document.
    /// This is the "I don't want this recording" action, not "I don't want this
    /// document".
    func delete(narration: NarrationRecord) {
        deleteEpisode(of: narration)
        storage.deleteWorkspace(narrationUuid: narration.uuid)
        dataManager.readAloud.deleteNarration(uuid: narration.uuid)
    }

    /// Deletes a document and everything it owns: every narration against it,
    /// their episodes and workspaces, and the retained source file.
    ///
    /// The reverse direction is deliberately not symmetric — deleting an
    /// *episode* only removes its narration (ADR-0019), because the document is
    /// the user's own content and a swipe on the Files screen must not destroy
    /// it.
    func delete(document: ReadAloudDocumentRecord) {
        for narration in dataManager.readAloud.deleteDocument(uuid: document.uuid) {
            deleteEpisode(of: narration)
            storage.deleteWorkspace(narrationUuid: narration.uuid)
        }
        storage.deleteSource(relativePath: document.sourcePath)
    }

    private func deleteEpisode(of narration: NarrationRecord) {
        guard let episodeUuid = narration.episodeUuid,
              let episode = dataManager.findUserEpisode(uuid: episodeUuid) else { return }
        UserEpisodeManager.deleteFromDevice(userEpisode: episode)
        dataManager.delete(userEpisodeUuid: episodeUuid)
    }
}
