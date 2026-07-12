import PocketCastsDataModel
import SwiftUI

/// Editor for a podcast's chapter smart-skip title patterns: chapters whose titles contain any of
/// these phrases (case-insensitive) are automatically deselected when chapters load.
struct PodcastSkipChaptersView: View {
    @EnvironmentObject private var theme: Theme
    @StateObject private var model: PodcastSkipChaptersViewModel

    init(podcast: Podcast) {
        _model = StateObject(wrappedValue: PodcastSkipChaptersViewModel(podcast: podcast))
    }

    var body: some View {
        List {
            Section(footer: Text(L10n.skipChaptersExplanation)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))) {
                HStack {
                    TextField(L10n.skipChaptersAddPlaceholder, text: $model.newPattern)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                        .onSubmit { model.addPattern() }
                    Button(action: { model.addPattern() }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(AppTheme.color(for: .primaryInteractive01, theme: theme))
                    }
                    .accessibilityLabel(L10n.skipChaptersAddButton)
                    .disabled(!model.canAddPattern)
                }
            }

            Section {
                if model.patterns.isEmpty {
                    Text(L10n.skipChaptersEmpty)
                        .font(.footnote)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                } else {
                    ForEach(model.patterns, id: \.self) { pattern in
                        Text(pattern)
                            .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                    }
                    .onDelete { offsets in
                        model.removePatterns(at: offsets)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.color(for: .primaryUi04, theme: theme).ignoresSafeArea())
    }
}

@MainActor
final class PodcastSkipChaptersViewModel: ObservableObject {
    @Published private(set) var patterns: [String]
    @Published var newPattern = ""

    private let podcastUuid: String

    init(podcast: Podcast) {
        podcastUuid = podcast.uuid
        patterns = podcast.settings.skipChapterTitles ?? []
    }

    var canAddPattern: Bool {
        let trimmed = newPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !patterns.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
    }

    func addPattern() {
        let trimmed = newPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !patterns.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            newPattern = ""
            return
        }

        patterns.append(trimmed)
        newPattern = ""
        persist()
    }

    func removePatterns(at offsets: IndexSet) {
        patterns.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        DataManager.sharedManager.saveSkipChapterTitles(patterns, podcastUuid: podcastUuid)
        NotificationCenter.postOnMainThread(notification: Constants.Notifications.podcastUpdated, object: podcastUuid)
        Analytics.track(.podcastSettingsSkipChaptersRulesChanged, properties: ["count": patterns.count])

        // Re-apply the rules to the currently loaded chapters if this podcast is playing
        if PlaybackManager.shared.currentPodcast?.uuid == podcastUuid {
            PlaybackManager.shared.forceUpdateChapterInfo()
        }
    }
}
