import Foundation
import PocketCastsTranscription
import XCTest

@testable import podcasts

/// Exercises the local model cache logic against a temp directory: downloaded
/// detection, deletion, disk usage and the cellular download gate. The actual
/// Hub download is deliberately untested (network); the gate throws before any
/// network work happens.
final class WhisperKitModelStoreTests: XCTestCase {
    private var baseURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisperkit-model-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: baseURL)
        try await super.tearDown()
    }

    private func makeStore(isUnexpensiveConnection: Bool = true,
                           allowCellularDownloads: Bool = false) -> WhisperKitModelStore {
        WhisperKitModelStore(baseURL: baseURL,
                             isUnexpensiveConnection: { isUnexpensiveConnection },
                             allowCellularDownloads: { allowCellularDownloads })
    }

    /// Lays down a fake variant folder in the Hub cache layout
    /// (`<base>/models/argmaxinc/whisperkit-coreml/<variant>/<model>.mlmodelc`).
    private func installFakeModel(variant: String,
                                  models: [String] = ["MelSpectrogram", "AudioEncoder", "TextDecoder"],
                                  fileBytes: Int = 16) throws {
        let store = makeStore()
        let folder = store.modelFolderURL(variant: variant)
        for model in models {
            let modelDir = folder.appendingPathComponent("\(model).mlmodelc", isDirectory: true)
            try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
            try Data(repeating: 0xAB, count: fileBytes).write(to: modelDir.appendingPathComponent("weights.bin"))
        }
    }

    // MARK: - Downloaded detection

    func testIsDownloadedRequiresAllThreeCoreModels() throws {
        let store = makeStore()
        XCTAssertFalse(store.isDownloaded(variant: "openai_whisper-tiny"))

        try installFakeModel(variant: "openai_whisper-tiny", models: ["MelSpectrogram", "AudioEncoder"])
        XCTAssertFalse(store.isDownloaded(variant: "openai_whisper-tiny"), "A partial download must read as not downloaded")

        try installFakeModel(variant: "openai_whisper-tiny")
        XCTAssertTrue(store.isDownloaded(variant: "openai_whisper-tiny"))
    }

    func testDownloadedVariantsListsOnlyModelsOnDisk() throws {
        let store = makeStore()
        XCTAssertTrue(store.downloadedVariants().isEmpty)

        try installFakeModel(variant: "openai_whisper-small")
        XCTAssertEqual(store.downloadedVariants().map(\.id), ["openai_whisper-small"])
    }

    func testDiarizerDownloadedDetectionRequiresAllModelFolders() throws {
        let store = makeStore()
        XCTAssertFalse(store.isDiarizerDownloaded())

        let repo = baseURL.appendingPathComponent("models/argmaxinc/speakerkit-coreml", isDirectory: true)
        for model in ["speaker_segmenter", "speaker_embedder"] {
            let dir = repo.appendingPathComponent("\(model)/pyannote-v3/W8A16", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("model".utf8).write(to: dir.appendingPathComponent("weights.bin"))
        }
        XCTAssertFalse(store.isDiarizerDownloaded(), "Missing clusterer must read as not downloaded")

        let clusterer = repo.appendingPathComponent("speaker_clusterer/pyannote-v4/W32A32", isDirectory: true)
        try FileManager.default.createDirectory(at: clusterer, withIntermediateDirectories: true)
        try Data("model".utf8).write(to: clusterer.appendingPathComponent("weights.bin"))
        XCTAssertTrue(store.isDiarizerDownloaded())
    }

    // MARK: - Delete / disk usage

    func testDeleteRemovesVariantFolder() throws {
        let store = makeStore()
        try installFakeModel(variant: "openai_whisper-base")
        XCTAssertTrue(store.isDownloaded(variant: "openai_whisper-base"))

        try store.delete(variant: "openai_whisper-base")

        XCTAssertFalse(store.isDownloaded(variant: "openai_whisper-base"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.modelFolderURL(variant: "openai_whisper-base").path))
        // Deleting a variant that isn't on disk is a no-op, not an error.
        XCTAssertNoThrow(try store.delete(variant: "openai_whisper-base"))
    }

    func testDiskUsageSumsEverythingUnderTheCacheRoot() throws {
        let store = makeStore()
        XCTAssertEqual(store.diskUsage(), 0)

        try installFakeModel(variant: "openai_whisper-tiny", fileBytes: 1024)

        // Allocated size is FS-block granular, so assert a lower bound (3 model
        // files x 1KB) rather than an exact byte count.
        XCTAssertGreaterThanOrEqual(store.diskUsage(), 3 * 1024)
    }

    // MARK: - Cellular gate

    func testDownloadRefusedOnCellularWhenNotAllowed() async {
        let store = makeStore(isUnexpensiveConnection: false, allowCellularDownloads: false)

        XCTAssertThrowsError(try store.ensureDownloadPermitted()) { error in
            XCTAssertEqual(error as? TranscriptionError, .modelDownloadFailed)
        }

        // The gate runs before any network work, so download must throw too.
        do {
            try await store.download(variant: "openai_whisper-tiny")
            XCTFail("Expected the cellular gate to refuse the download")
        } catch {
            XCTAssertEqual(error as? TranscriptionError, .modelDownloadFailed)
        }
    }

    func testDownloadPermittedOnCellularWhenUserOptedIn() {
        let store = makeStore(isUnexpensiveConnection: false, allowCellularDownloads: true)
        XCTAssertNoThrow(try store.ensureDownloadPermitted())
    }

    func testDownloadPermittedOnUnexpensiveConnectionRegardlessOfToggle() {
        let store = makeStore(isUnexpensiveConnection: true, allowCellularDownloads: false)
        XCTAssertNoThrow(try store.ensureDownloadPermitted())
    }
}
