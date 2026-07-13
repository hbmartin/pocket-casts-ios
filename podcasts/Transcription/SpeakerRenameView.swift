import PocketCastsDataModel
import SwiftUI

/// Sheet for renaming the diarized speakers of a generated transcript
/// ("Speaker 1…N" → custom names). Names persist as a JSON object on the
/// episode's transcription record and are substituted into the VTT at load
/// time — the artifact on disk stays canonical, so a rename never rewrites
/// the file or the FTS index.
struct SpeakerRenameView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.dismiss) private var dismiss

    let episodeUuid: String
    let speakerCount: Int

    /// Called after a save committed, so the presenter can reload the transcript.
    let onSaved: () -> Void

    @State private var names: [String]

    init(episodeUuid: String, speakerCount: Int, currentNames: [String: String], onSaved: @escaping () -> Void) {
        self.episodeUuid = episodeUuid
        self.speakerCount = max(1, speakerCount)
        self.onSaved = onSaved
        _names = State(initialValue: (1 ... max(1, speakerCount)).map { currentNames[Self.canonicalName(forSpeaker: $0)] ?? "" })
    }

    var body: some View {
        NavigationStack {
            List {
                Section(
                    footer: Text(L10n.transcriptionRenameFooter)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                ) {
                    ForEach(0 ..< speakerCount, id: \.self) { index in
                        HStack {
                            // The canonical id is data (it appears verbatim in the
                            // VTT artifact), not localizable UI chrome.
                            Text(verbatim: Self.canonicalName(forSpeaker: index + 1))
                                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                            TextField(L10n.transcriptionRenamePlaceholder, text: $names[index])
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.color(for: .primaryUi04, theme: theme).ignoresSafeArea())
            .navigationTitle(L10n.transcriptionRenameSpeakers)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.transcriptionRenameSave) { save() }
                }
            }
        }
    }

    // MARK: - Names

    /// The canonical speaker id the aligner writes into the VTT voice tags.
    nonisolated static func canonicalName(forSpeaker index: Int) -> String {
        "Speaker \(index)"
    }

    /// Decodes a record's `speakerNames` JSON (`{"Speaker 1":"Alice"}`); an
    /// unreadable or missing payload is an empty mapping.
    nonisolated static func decodeNames(_ json: String?) -> [String: String] {
        guard let json, let data = json.data(using: .utf8),
              let names = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return names
    }

    private func save() {
        var custom: [String: String] = [:]
        for (index, name) in names.enumerated() {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            custom[Self.canonicalName(forSpeaker: index + 1)] = trimmed
        }

        // Clearing every field removes the payload entirely, restoring the
        // canonical numbered names.
        let json: String? = custom.isEmpty
            ? nil
            : (try? JSONEncoder().encode(custom)).flatMap { String(data: $0, encoding: .utf8) }
        DataManager.sharedManager.transcriptions.setSpeakerNames(episodeUuid: episodeUuid, namesJSON: json)

        Analytics.track(.transcriptionSpeakerRenamed, properties: [
            "speaker_count": speakerCount,
            "renamed_count": custom.count
        ])

        onSaved()
        dismiss()
    }
}
