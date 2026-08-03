import PocketCastsDataModel
import PocketCastsUtils
import SwiftUI

/// "Mentioned Books" (Highlights S11): every book the Mentioned Entity
/// substrate has seen, most-cited first — library-wide from the Profile tab,
/// or scoped to one show ("most-cited books on this show").
struct BookDirectoryView: View {
    @EnvironmentObject private var theme: Theme
    @StateObject private var model: BookDirectoryModel

    init(podcastUuid: String? = nil) {
        _model = StateObject(wrappedValue: BookDirectoryModel(podcastUuid: podcastUuid))
    }

    var body: some View {
        Group {
            if model.isLoading {
                ProgressView()
                    .tint(AppTheme.loadingActivityColor().color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.books.isEmpty {
                EmptyStateView(title: L10n.bookDirectoryEmptyTitle,
                               message: L10n.bookDirectoryEmptyMessage,
                               icon: { Image(systemName: "book.closed") })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.books, id: \.canonicalKey) { book in
                    NavigationLink {
                        EntityDetailView(kind: .book, canonicalKey: book.canonicalKey, displayName: book.displayName)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "book.closed")
                                .foregroundStyle(AppTheme.color(for: .primaryIcon02, theme: theme))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(book.displayName)
                                    .font(style: .body, weight: .medium)
                                    .foregroundStyle(AppTheme.color(for: .primaryText01, theme: theme))
                                Text(subtitle(for: book))
                                    .font(style: .footnote)
                                    .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                            }
                        }
                    }
                    .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(AppTheme.color(for: .primaryUi01, theme: theme).ignoresSafeArea())
        .navigationTitle(L10n.bookDirectoryTitle)
        .onAppear { model.load() }
    }

    private func subtitle(for book: MentionedEntityAggregate) -> String {
        book.episodeCount == 1
            ? L10n.bookDirectoryEpisodeCountSingular
            : L10n.bookDirectoryEpisodeCountPlural(String(book.episodeCount))
    }
}

@MainActor
final class BookDirectoryModel: ObservableObject {
    @Published private(set) var books: [MentionedEntityAggregate] = []
    @Published private(set) var isLoading = true

    private let podcastUuid: String?
    private var hasStartedLoading = false
    private let loadBooks: @Sendable (String?) async -> [MentionedEntityAggregate]

    init(podcastUuid: String? = nil,
         loadBooks: (@Sendable (String?) async -> [MentionedEntityAggregate])? = nil) {
        self.podcastUuid = podcastUuid
        self.loadBooks = loadBooks ?? { podcastUuid in
            if let podcastUuid {
                DataManager.sharedManager.mentionedEntities.mostCited(kind: .book, podcastUuid: podcastUuid)
            } else {
                DataManager.sharedManager.mentionedEntities.entitiesAcrossLibrary(kind: .book)
            }
        }
    }

    func load() {
        guard !hasStartedLoading else { return }
        hasStartedLoading = true
        let podcastUuid = podcastUuid
        let loadBooks = loadBooks
        // Detached: an inherited Task (and, under approachable concurrency,
        // the nonisolated async closure it awaits) would run the library-wide
        // aggregate query on the main actor.
        Task.detached { [weak self] in
            let books = await loadBooks(podcastUuid)
            await MainActor.run {
                self?.books = books
                self?.isLoading = false
                Analytics.track(.bookDirectoryShown, properties: ["book_count": books.count])
            }
        }
    }
}
