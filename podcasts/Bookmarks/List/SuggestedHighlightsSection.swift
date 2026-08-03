import PocketCastsDataModel
import PocketCastsUtils
import SwiftUI

/// The Suggested Highlights review strip (Highlights S8): pending machine
/// suggestions rendered above the bookmark list, each with keep/dismiss.
/// Self-contained — drops into every `BookmarksListView` surface and hides
/// itself when the flag is off or nothing is pending.
struct SuggestedHighlightsSection<ListStyle: BookmarksStyle>: View {
    enum Scope {
        case all
        case episode(String?)
    }

    @ObservedObject var style: ListStyle
    @StateObject private var model = SuggestedHighlightsSectionModel()

    /// Restricts player/episode surfaces even while their episode is loading.
    var scope: Scope = .all

    private var suggestions: [SalientSegmentRecord] {
        model.suggestions(for: scope)
    }

    var body: some View {
        if FeatureFlag.suggestedHighlights.enabled, !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.suggestedHighlightsTitle)
                    .font(style: .footnote, weight: .semibold)
                    .foregroundStyle(style.secondaryText)

                ForEach(suggestions, id: \.id) { suggestion in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                                .font(style: .subheadline, weight: .medium)
                                .foregroundStyle(style.primaryText)
                                .lineLimit(1)
                            if let excerpt = suggestion.excerpt, !excerpt.isEmpty {
                                Text(excerpt)
                                    .font(style: .footnote)
                                    .foregroundStyle(style.secondaryText)
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: 8)
                        Button {
                            model.accept(suggestion)
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.suggestedHighlightKeep)
                        Button {
                            model.dismiss(suggestion)
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.suggestedHighlightDismiss)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, BookmarkListConstants.padding)
            .padding(.vertical, 8)
            .task { model.reload() }
        }
    }
}

@MainActor
final class SuggestedHighlightsSectionModel: ObservableObject {
    @Published private(set) var pending: [SalientSegmentRecord] = []

    private let updateToken = ObservationTokenBox()
    private let manager = SuggestedHighlightsManager()
    private let dataManager: DataManager

    init(dataManager: DataManager = .sharedManager) {
        self.dataManager = dataManager
        updateToken.token = NotificationCenter.default.addObserver(for: SuggestedHighlightsUpdated.self) { [weak self] _ in
            self?.reload()
        }
        reload()
    }

    func suggestions<ListStyle>(for scope: SuggestedHighlightsSection<ListStyle>.Scope) -> [SalientSegmentRecord] {
        switch scope {
        case .all:
            return pending
        case .episode(let episodeUuid):
            guard let episodeUuid else { return [] }
            return pending.filter { $0.episodeUuid == episodeUuid }
        }
    }

    func reload() {
        pending = dataManager.salientSegments.pendingSuggestions()
    }

    func accept(_ suggestion: SalientSegmentRecord) {
        Task { await manager.accept(suggestion) }
    }

    func dismiss(_ suggestion: SalientSegmentRecord) {
        manager.dismiss(suggestion)
    }
}

extension SalientSegmentRecord {
    /// Stable SwiftUI identity within the strip.
    var id: String { "\(episodeUuid)-\(rank)" }
}
