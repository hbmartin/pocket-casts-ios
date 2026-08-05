import Foundation
import PocketCastsDataModel
import PocketCastsReadAloud
import UniformTypeIdentifiers

/// Creates narrations: extract the text, retain the source, write the row.
///
/// The one place a `Narration` is born, so every entry point — picker, compose
/// screen, share sheet, App Intent — produces identically shaped rows. Rendering
/// is `NarrationQueue`'s job; this type never speaks.
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

    /// Retains the source and writes the narration row.
    ///
    /// Voice and rate are written here and never mutated afterwards. That is
    /// what makes the resume checkpoint sound: rendered chunks can never
    /// disagree with the settings a later run reads back. Re-narrating with a
    /// different voice creates a new row and a new workspace.
    func commit(
        preview: Preview,
        title: String,
        engine: NarrationEngineKind,
        providerId: String?,
        voice: SynthesisVoice,
        settings: SynthesisSettings
    ) throws -> NarrationRecord {
        let uuid = UUID().uuidString.lowercased()

        let sourcePath: String
        if let composedText = preview.composedText {
            sourcePath = try storage.writeSource(text: composedText, narrationUuid: uuid)
        } else if let sourceURL = preview.sourceURL {
            sourcePath = try storage.importSource(from: sourceURL, narrationUuid: uuid)
        } else {
            throw ReadAloudError.sourceUnreadable
        }

        var record = NarrationRecord()
        record.uuid = uuid
        record.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? preview.document.suggestedTitle
            : title
        record.originalFilename = preview.originalFilename
        record.source = preview.sourceKind
        record.utType = preview.utType?.identifier
        record.sourcePath = sourcePath
        record.characterCount = Int32(preview.document.characterCount)
        record.language = preview.document.detectedLanguage
        record.engine = engine
        record.providerId = providerId
        record.voiceId = voice.id
        record.voiceName = voice.name
        record.rate = Double(settings.rate)
        record.narrationState = .queued
        record.createdDate = Date().timeIntervalSince1970

        guard dataManager.narrations.add(record) else {
            storage.deleteSource(relativePath: sourcePath)
            throw ReadAloudError.engineFailure
        }
        return record
    }

    // MARK: - Deletion

    /// Deletes a narration and everything it owns: the source document, any
    /// workspace, and the generated episode.
    ///
    /// The reverse direction is not symmetric — deleting the *episode* only
    /// detaches (ADR-0019), because the document is the user's own content and a
    /// swipe on the Files screen must not destroy it.
    func delete(narration: NarrationRecord) {
        if let episodeUuid = narration.episodeUuid,
           let episode = dataManager.findUserEpisode(uuid: episodeUuid) {
            UserEpisodeManager.deleteFromDevice(userEpisode: episode)
            dataManager.delete(userEpisodeUuid: episodeUuid)
        }
        storage.deleteWorkspace(narrationUuid: narration.uuid)
        storage.deleteSource(relativePath: narration.sourcePath)
        dataManager.narrations.delete(uuid: narration.uuid)
    }
}
