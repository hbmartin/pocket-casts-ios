import Foundation
import PocketCastsTranscription
import PocketCastsUtils
@preconcurrency import WhisperKit

/// Owns the on-disk cache of transcription models under
/// `Documents/transcription_models`: the WhisperKit ASR variants and the
/// SpeakerKit diarizer models share one Hub-layout tree
/// (`<base>/models/<repo>/…`) so a single disk-usage figure covers both.
///
/// Also owns the cellular download gate: model downloads are refused on
/// expensive connections unless `Settings.transcriptionAllowCellularModelDownloads`
/// is on. The connectivity and settings reads are injected closures so tests can
/// exercise the gate without a network stack.
nonisolated struct WhisperKitModelStore: Sendable {
    /// A user-selectable WhisperKit model. `id` is the model's folder name in the
    /// `argmaxinc/whisperkit-coreml` repo and the value persisted by
    /// `Settings.transcriptionWhisperModel`.
    struct Variant: Identifiable, Equatable, Sendable {
        let id: String
        let displayName: String
        /// Download size shown before the model is on disk. Approximate — the
        /// repo evolves; once downloaded the UI shows the real on-disk size.
        let approximateSizeMB: Int
    }

    /// The curated variant set from the transcription plan (tiny/base/small/
    /// large-v3-turbo). All are multilingual; "large-v3-turbo" maps to the
    /// repo's compressed `v20240930` (turbo) build so it stays phone-sized.
    static let curatedVariants: [Variant] = [
        Variant(id: "openai_whisper-tiny", displayName: L10n.transcriptionModelTiny, approximateSizeMB: 80),
        Variant(id: "openai_whisper-base", displayName: L10n.transcriptionModelBase, approximateSizeMB: 150),
        Variant(id: "openai_whisper-small", displayName: L10n.transcriptionModelSmall, approximateSizeMB: 500),
        Variant(id: "openai_whisper-large-v3-v20240930_626MB", displayName: L10n.transcriptionModelLargeTurbo, approximateSizeMB: 626)
    ]

    /// Matches the package's "small" recommendation for podcast-length audio:
    /// the default in `Settings.transcriptionWhisperModel`.
    static let defaultVariantId = "openai_whisper-small"

    static let whisperRepo = "argmaxinc/whisperkit-coreml"
    static let speakerKitRepo = "argmaxinc/speakerkit-coreml"

    static let defaultBaseURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Documents/transcription_models", isDirectory: true)

    /// Hub download base (`downloadBase` in WhisperKit/SpeakerKit terms). Repos
    /// cache under `<baseURL>/models/<repoId>/…`.
    let baseURL: URL

    private let isUnexpensiveConnection: @Sendable () -> Bool
    private let allowCellularDownloads: @Sendable () -> Bool

    init(baseURL: URL = WhisperKitModelStore.defaultBaseURL,
         isUnexpensiveConnection: @escaping @Sendable () -> Bool = { NetworkUtils.shared.isConnectedToUnexpensiveConnection() },
         allowCellularDownloads: @escaping @Sendable () -> Bool = { Settings.transcriptionAllowCellularModelDownloads() }) {
        self.baseURL = baseURL
        self.isUnexpensiveConnection = isUnexpensiveConnection
        self.allowCellularDownloads = allowCellularDownloads
    }

    // MARK: - Layout

    /// Local folder for a WhisperKit variant, mirroring the Hub cache layout
    /// `WhisperKit.download` writes into (`<base>/models/<repo>/<variant>`).
    func modelFolderURL(variant: String) -> URL {
        repoURL(Self.whisperRepo).appendingPathComponent(variant, isDirectory: true)
    }

    private func repoURL(_ repo: String) -> URL {
        repo.split(separator: "/").reduce(baseURL.appendingPathComponent("models", isDirectory: true)) {
            $0.appendingPathComponent(String($1), isDirectory: true)
        }
    }

    // MARK: - Downloaded state

    /// True when the variant's folder holds all three CoreML pipeline models —
    /// a partial download (missing decoder, interrupted snapshot) reads as not
    /// downloaded so the UI re-offers the download.
    func isDownloaded(variant: String) -> Bool {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: modelFolderURL(variant: variant).path)) ?? []
        return ["MelSpectrogram", "AudioEncoder", "TextDecoder"].allSatisfy { model in
            contents.contains { $0.hasPrefix(model) }
        }
    }

    func downloadedVariants() -> [Variant] {
        Self.curatedVariants.filter { isDownloaded(variant: $0.id) }
    }

    /// True when the SpeakerKit pyannote model set is on disk. Mirrors
    /// `ModelDownloader.patternsExistLocally`: every model's top-level folder in
    /// the repo cache must exist and be non-empty.
    func isDiarizerDownloaded() -> Bool {
        let repo = repoURL(Self.speakerKitRepo)
        return ["speaker_segmenter", "speaker_embedder", "speaker_clusterer"].allSatisfy { model in
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: repo.appendingPathComponent(model).path)) ?? []
            return !contents.isEmpty
        }
    }

    // MARK: - Disk usage / delete

    /// Total bytes of everything under the model cache root (all Whisper
    /// variants, tokenizers, and the diarizer models).
    func diskUsage() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: baseURL,
                                                              includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey],
                                                              options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }

    /// Removes the variant's model folder. The shared tokenizer cache (~2MB per
    /// model family) is left in place — other variants may still use it.
    func delete(variant: String) throws {
        let folder = modelFolderURL(variant: variant)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        try FileManager.default.removeItem(at: folder)
    }

    // MARK: - Cellular gate

    /// Model downloads are refused on cellular/expensive connections unless the
    /// user opted in. `TranscriptionError` carries no message payload, so the
    /// clear explanation goes to the log and the settings UI shows its own
    /// cellular-specific copy (`L10n.transcriptionModelCellularBlocked`).
    func ensureDownloadPermitted() throws {
        guard !isUnexpensiveConnection() else { return }
        guard allowCellularDownloads() else {
            FileLog.shared.addMessage("[Transcription] model download refused: on a cellular/expensive connection and cellular model downloads are disabled")
            throw TranscriptionError.modelDownloadFailed
        }
    }

    // MARK: - Download

    /// Downloads a WhisperKit variant into the cache (no-op re-download is safe:
    /// the Hub snapshot skips files already on disk). Respects the cellular gate.
    /// Returns the model folder.
    @discardableResult
    func download(variant: String, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        try ensureDownloadPermitted()
        try ensureBaseDirectoryExists()
        do {
            return try await WhisperKit.download(variant: variant,
                                                 downloadBase: baseURL,
                                                 from: Self.whisperRepo) { hubProgress in
                progress(min(max(hubProgress.fractionCompleted, 0), 1))
            }
        } catch is CancellationError {
            throw TranscriptionError.cancelled
        } catch {
            FileLog.shared.addMessage("[Transcription] WhisperKit model download failed (\(variant)): \(error.localizedDescription)")
            throw TranscriptionError.modelDownloadFailed
        }
    }

    /// Creates the cache root and excludes it from backups (models are
    /// re-downloadable). Called before any download writes into the tree —
    /// including the SpeakerKit path, which shares the same base.
    func ensureBaseDirectoryExists() throws {
        guard !FileManager.default.fileExists(atPath: baseURL.path) else { return }
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        SJCommonUtils.setDontBackupFlag(baseURL)
    }
}
