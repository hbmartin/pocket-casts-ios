import Foundation
import PocketCastsTranscription

/// Owns the on-disk WebVTT artifacts for locally generated transcripts:
/// `Documents/generated_transcripts/{episodeUuid}.vtt`.
///
/// The directory deliberately lives outside `podcasts_non_backed_up` — generated
/// transcripts outlive deleted audio — but is still excluded from device backups
/// because transcripts are regenerable.
nonisolated struct TranscriptionArtifactStore: Sendable {
    static let defaultDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Documents/generated_transcripts", isDirectory: true)

    private let directoryURL: URL

    init(directoryURL: URL = TranscriptionArtifactStore.defaultDirectoryURL) {
        self.directoryURL = directoryURL
    }

    func fileURL(forEpisodeUuid episodeUuid: String) -> URL {
        directoryURL.appendingPathComponent("\(episodeUuid).vtt", isDirectory: false)
    }

    /// Serializes the transcript to VTT and writes it as the episode's artifact,
    /// replacing any previous one. Returns the artifact URL (persisted in the
    /// transcription record's `filePath`).
    @discardableResult
    func write(transcript: DiarizedTranscript, episodeUuid: String) throws -> URL {
        try ensureDirectoryExists()
        let url = fileURL(forEpisodeUuid: episodeUuid)
        try VTTSerializer.serialize(transcript).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// The episode's raw VTT artifact, or nil when none exists.
    func read(episodeUuid: String) -> String? {
        try? String(contentsOf: fileURL(forEpisodeUuid: episodeUuid), encoding: .utf8)
    }

    /// Whether the episode's VTT artifact exists on disk. A completed record
    /// without its artifact (the directory is excluded from device backups, the
    /// database is not) must not be treated as a usable transcript.
    func hasArtifact(episodeUuid: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(forEpisodeUuid: episodeUuid).path)
    }

    func delete(episodeUuid: String) {
        try? FileManager.default.removeItem(at: fileURL(forEpisodeUuid: episodeUuid))
        deleteFingerprint(episodeUuid: episodeUuid)
    }

    // MARK: - Contribution fingerprint cache

    /// Where the contribution pipeline caches the episode's gzipped
    /// `fingerprint-compact-v2` JSON, next to the VTT artifact, so upload
    /// retries never re-decode the audio (docs/TranscriptContributions.md §2).
    func fingerprintFileURL(forEpisodeUuid episodeUuid: String) -> URL {
        directoryURL.appendingPathComponent("\(episodeUuid)-fingerprint.json.gz", isDirectory: false)
    }

    /// The cached gzipped fingerprint, or nil when none has been computed yet.
    func readFingerprint(episodeUuid: String) -> Data? {
        try? Data(contentsOf: fingerprintFileURL(forEpisodeUuid: episodeUuid))
    }

    /// Caches the gzipped fingerprint bytes for the episode, replacing any
    /// previous cache.
    @discardableResult
    func writeFingerprint(_ data: Data, episodeUuid: String) throws -> URL {
        try ensureDirectoryExists()
        let url = fingerprintFileURL(forEpisodeUuid: episodeUuid)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Removes the cached fingerprint (upload accepted, or transcription deleted).
    func deleteFingerprint(episodeUuid: String) {
        try? FileManager.default.removeItem(at: fingerprintFileURL(forEpisodeUuid: episodeUuid))
    }

    /// Total bytes of all generated transcript artifacts on disk. Backs the
    /// storage accounting row in transcription settings.
    func totalDiskUsage() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directoryURL,
                                                                       includingPropertiesForKeys: [.fileSizeKey],
                                                                       options: [.skipsHiddenFiles]) else {
            return 0
        }
        return files.reduce(into: Int64(0)) { total, fileURL in
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
    }

    /// Applies user speaker renames (`{"Speaker 1":"Alice"}` JSON from the
    /// transcription record) to a raw VTT string before parsing.
    ///
    /// Substituting inside the `<v Speaker N>` voice tags covers both cue
    /// attribution and the speaker headers `TranscriptModel` derives from those
    /// tags at parse time. The VTT file on disk stays canonical ("Speaker N"),
    /// so renames never require an artifact rewrite or FTS rebuild.
    static func applyingSpeakerNames(vtt: String, namesJSON: String?) -> String {
        guard let namesJSON,
              let data = namesJSON.data(using: .utf8),
              let names = try? JSONDecoder().decode([String: String].self, from: data),
              !names.isEmpty else {
            return vtt
        }

        var result = vtt
        // Longest original names first so "Speaker 10" is renamed before
        // "Speaker 1" could match its prefix.
        for (speaker, customName) in names.sorted(by: { $0.key.count > $1.key.count }) {
            let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            result = result.replacingOccurrences(of: "<v \(speaker)>", with: "<v \(escapeVoiceTagName(trimmed))>")
        }
        return result
    }

    // MARK: - Private

    private func ensureDirectoryExists() throws {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: directoryURL.path) else { return }
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        // Regenerable content: keep it out of iCloud/iTunes backups.
        SJCommonUtils.setDontBackupFlag(directoryURL)
    }

    /// Escapes the characters WebVTT reserves so a user-chosen name can't break
    /// the `<v …>` tag it is substituted into.
    private static func escapeVoiceTagName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
