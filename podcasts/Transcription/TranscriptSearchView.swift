import PocketCastsDataModel
import PocketCastsUtils
import SwiftUI

/// Cross-episode search over locally generated transcripts (Profile → Search
/// Transcripts). Results are grouped by episode; tapping a row plays that
/// episode from the matched timestamp and pops back to the player.
struct TranscriptSearchView: View {
    @EnvironmentObject private var theme: Theme
    @StateObject private var model = TranscriptSearchViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            searchField
            content
        }
        .background(AppTheme.color(for: .primaryUi04, theme: theme).ignoresSafeArea())
        .onAppear {
            Analytics.track(.transcriptionSearchShown)
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppTheme.color(for: .primaryIcon02, theme: theme))
            TextField(L10n.transcriptionSearchPrompt, text: $model.searchTerm)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
            if !model.searchTerm.isEmpty {
                Button {
                    model.searchTerm = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppTheme.color(for: .primaryIcon02, theme: theme))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.transcriptionSearchClear)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppTheme.color(for: .primaryField01, theme: theme))
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            zeroState(title: L10n.transcriptionSearchEmptyTitle,
                      message: L10n.transcriptionSearchEmptyMessage)
        case .searching:
            VStack {
                Spacer()
                ProgressView()
                    .tint(AppTheme.color(for: .primaryIcon02, theme: theme))
                Spacer()
            }
        case .noResults:
            zeroState(title: L10n.transcriptionSearchNoResultsTitle,
                      message: L10n.transcriptionSearchNoResultsMessage(model.searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)))
        case .results:
            resultsList
        }
    }

    private func zeroState(title: String, message: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundColor(AppTheme.color(for: .primaryIcon02, theme: theme))
                .padding(.bottom, 8)
            Text(title)
                .font(.headline)
                .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
            Text(message)
                .font(.subheadline)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }

    private var resultsList: some View {
        List {
            ForEach(model.sections) { section in
                Section(header: sectionHeader(section)) {
                    ForEach(section.rows) { row in
                        Button {
                            if model.play(row: row) {
                                dismiss()
                            }
                        } label: {
                            resultRow(row)
                        }
                        .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    private func sectionHeader(_ section: TranscriptSearchViewModel.EpisodeSection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(section.episodeTitle)
                .font(.footnote.weight(.semibold))
                .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
            if let podcastTitle = section.podcastTitle {
                Text(podcastTitle)
                    .font(.caption)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            }
        }
        .textCase(nil)
    }

    private func resultRow(_ row: TranscriptSearchViewModel.ResultRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            snippetText(row.runs)
                .font(.subheadline)
                .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                .multilineTextAlignment(.leading)
            HStack(spacing: 4) {
                Image(systemName: "play.fill")
                    .font(.caption2)
                Text(TimeFormatter.shared.playTimeFormat(time: row.startTime))
                    .font(.caption)
            }
            .foregroundColor(AppTheme.color(for: .primaryInteractive01, theme: theme))
        }
        .padding(.vertical, 2)
    }

    /// Concatenates the snippet runs into one Text, bolding the matched terms.
    private func snippetText(_ runs: [TranscriptSearchViewModel.SnippetRun]) -> Text {
        runs.reduce(Text(verbatim: "")) { text, run in
            text + Text(verbatim: run.text).fontWeight(run.isHighlighted ? .bold : .regular)
        }
    }
}
