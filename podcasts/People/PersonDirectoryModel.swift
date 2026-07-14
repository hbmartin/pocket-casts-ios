import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// One episode a Person appears in, with the canonical diarization label
/// ("Speaker 2") that maps the person back to that episode's indexed segments.
nonisolated struct PersonAppearance: Hashable, Sendable {
    let episodeUuid: String
    let podcastUuid: String?
    let canonicalSpeaker: String
}

/// A Person in the v1 identity model: a distinct display name. Two humans who
/// share a name merge into one entry — accepted for v1, where every name was
/// typed by the user in the speaker-rename sheet.
nonisolated struct PersonDirectoryEntry: Identifiable, Hashable, Sendable {
    let displayName: String
    let appearances: [PersonAppearance]

    var id: String { displayName }
}

/// Pure aggregation: per-episode speaker-rename JSON in, name-keyed directory
/// entries out. Appearances whose episode no longer resolves are dropped (the
/// record can outlive the episode row).
nonisolated enum PersonDirectoryBuilder {
    static func entries(from records: [EpisodeTranscriptionRecord],
                        episodeExists: (String) -> Bool) -> [PersonDirectoryEntry] {
        var appearancesByName: [String: [PersonAppearance]] = [:]

        for record in records {
            guard episodeExists(record.episodeUuid) else { continue }
            for (canonicalSpeaker, rawName) in SpeakerRenameView.decodeNames(record.speakerNames) {
                let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                appearancesByName[name, default: []].append(PersonAppearance(
                    episodeUuid: record.episodeUuid,
                    podcastUuid: record.podcastUuid,
                    canonicalSpeaker: canonicalSpeaker
                ))
            }
        }

        return appearancesByName
            .map { PersonDirectoryEntry(displayName: $0.key, appearances: $0.value) }
            .sorted {
                if $0.appearances.count != $1.appearances.count {
                    return $0.appearances.count > $1.appearances.count
                }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }
}

/// Drives the People directory screen: loads renamed speakers off-main and
/// publishes the aggregated entries.
@MainActor
final class PersonDirectoryModel: ObservableObject {
    @Published private(set) var entries: [PersonDirectoryEntry] = []
    @Published private(set) var hasLoaded = false

    private let recordsProvider: @Sendable () -> [EpisodeTranscriptionRecord]
    private let episodeExists: @Sendable (String) -> Bool

    init(recordsProvider: @escaping @Sendable () -> [EpisodeTranscriptionRecord] = {
             DataManager.sharedManager.transcriptions.recordsWithSpeakerNames()
         },
         episodeExists: @escaping @Sendable (String) -> Bool = {
             DataManager.sharedManager.findBaseEpisode(uuid: $0) != nil
         }) {
        self.recordsProvider = recordsProvider
        self.episodeExists = episodeExists
    }

    func load() {
        let recordsProvider = recordsProvider
        let episodeExists = episodeExists
        Task.detached(priority: .userInitiated) { [weak self] in
            let entries = PersonDirectoryBuilder.entries(from: recordsProvider(), episodeExists: episodeExists)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.entries = entries
                self.hasLoaded = true
            }
        }
    }
}
