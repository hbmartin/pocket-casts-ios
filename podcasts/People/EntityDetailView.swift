import PocketCastsDataModel
import PocketCastsUtils
import SwiftUI

/// One entity's appearances across the library (Highlights S11): tap a
/// transcript mention to play from that moment; the "N shows you follow
/// mentioned this" line rides the subscribed-podcast set.
struct EntityDetailView: View {
    @EnvironmentObject private var theme: Theme
    @StateObject private var model: EntityDetailModel

    private let displayName: String

    init(kind: MentionedEntityKind, canonicalKey: String, displayName: String) {
        self.displayName = displayName
        _model = StateObject(wrappedValue: EntityDetailModel(kind: kind, canonicalKey: canonicalKey))
    }

    var body: some View {
        List {
            if model.followedShowCount > 0 {
                Section {
                    Text(model.followedShowCount == 1
                        ? L10n.entityDetailFollowedShowsSingular
                        : L10n.entityDetailFollowedShowsPlural(String(model.followedShowCount)))
                        .font(style: .footnote, weight: .semibold)
                        .foregroundStyle(AppTheme.color(for: .support02, theme: theme))
                }
                .listRowBackground(AppTheme.color(for: .primaryUi02, theme: theme))
            }

            Section {
                ForEach(model.appearances, id: \.rowIdentity) { appearance in
                    Button {
                        model.play(appearance)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.episodeTitle(for: appearance))
                                .font(style: .body, weight: .medium)
                                .foregroundStyle(AppTheme.color(for: .primaryText01, theme: theme))
                                .lineLimit(2)
                            Text(model.subtitle(for: appearance))
                                .font(style: .footnote)
                                .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                        }
                    }
                    .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))
                }
            } header: {
                Text(L10n.entityDetailAppearances)
                    .font(style: .footnote, weight: .semibold)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppTheme.color(for: .primaryUi01, theme: theme).ignoresSafeArea())
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.load() }
    }
}

@MainActor
final class EntityDetailModel: ObservableObject {
    @Published private(set) var appearances: [MentionedEntityRecord] = []
    @Published private(set) var followedShowCount = 0

    private var episodeTitles: [String: String] = [:]
    private var podcastTitles: [String: String] = [:]
    private var hasStartedLoading = false

    private let kind: MentionedEntityKind
    private let canonicalKey: String

    init(kind: MentionedEntityKind, canonicalKey: String) {
        self.kind = kind
        self.canonicalKey = canonicalKey
    }

    func load() {
        guard !hasStartedLoading else { return }
        hasStartedLoading = true
        let kind = kind
        let canonicalKey = canonicalKey

        // Detached: an inherited Task would stay on the main actor (this
        // target's default isolation) and run every GRDB read in these
        // library-wide aggregates on the main thread.
        Task.detached { [weak self] in
            let dataManager = DataManager.sharedManager
            let rows = dataManager.mentionedEntities.appearances(kind: kind, canonicalKey: canonicalKey)

            // Deduplicate by episode+source for display; resolve titles once.
            var seen = Set<String>()
            let display = rows.filter { seen.insert($0.rowIdentity).inserted }

            var episodeTitles: [String: String] = [:]
            var podcastTitles: [String: String] = [:]
            for row in display {
                if episodeTitles[row.episodeUuid] == nil {
                    episodeTitles[row.episodeUuid] = dataManager.findBaseEpisode(uuid: row.episodeUuid)?.displayableTitle()
                }
                if let podcastUuid = row.podcastUuid, podcastTitles[podcastUuid] == nil {
                    podcastTitles[podcastUuid] = dataManager.findPodcast(uuid: podcastUuid)?.title
                }
            }

            let subscribed = dataManager.allPodcasts(includeUnsubscribed: false).map(\.uuid)
            let followedShows = dataManager.mentionedEntities.podcastUuidsMentioning(
                kind: kind, canonicalKey: canonicalKey, within: subscribed)

            await MainActor.run { [weak self] in
                self?.appearances = display
                self?.episodeTitles = episodeTitles
                self?.podcastTitles = podcastTitles
                self?.followedShowCount = followedShows.count
            }
        }
    }

    func episodeTitle(for appearance: MentionedEntityRecord) -> String {
        episodeTitles[appearance.episodeUuid] ?? L10n.bookmarksExportUnknownEpisode
    }

    func subtitle(for appearance: MentionedEntityRecord) -> String {
        var parts: [String] = []
        if let podcastUuid = appearance.podcastUuid, let title = podcastTitles[podcastUuid] {
            parts.append(title)
        }
        if let startTime = appearance.startTime {
            parts.append(L10n.entityDetailMentionedAt(TimeFormatter.shared.playTimeFormat(time: startTime)))
        } else if let role = appearance.role, !role.isEmpty {
            parts.append(role.localizedCapitalized)
        }
        return parts.joined(separator: " · ")
    }

    func play(_ appearance: MentionedEntityRecord) {
        PlaybackManager.shared.play(
            episodeUuid: appearance.episodeUuid,
            podcastUuid: appearance.podcastUuid,
            at: appearance.startTime ?? 0
        )
        Analytics.track(.entityDetailAppearanceTapped, properties: [
            "kind": appearance.kind,
            "source": appearance.source
        ])
    }
}

nonisolated extension MentionedEntityRecord {
    /// Display identity: one row per episode+source.
    var rowIdentity: String { "\(episodeUuid)-\(source)" }
}
