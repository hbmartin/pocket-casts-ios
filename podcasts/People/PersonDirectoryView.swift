import PocketCastsUtils
import SwiftUI

/// The People directory: every person the user has named in a transcript's
/// speaker-rename sheet, most-appearing first. Reached from the Profile tab.
struct PersonDirectoryView: View {
    @EnvironmentObject private var theme: Theme
    @StateObject private var model = PersonDirectoryModel()

    var body: some View {
        Group {
            if model.entries.isEmpty {
                if model.hasLoaded {
                    EmptyStateView(title: L10n.peopleDirectoryEmptyTitle,
                                   message: L10n.peopleDirectoryEmptyMessage,
                                   icon: { Image(systemName: "person.2") })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .tint(AppTheme.loadingActivityColor().color)
                }
            } else {
                List {
                    ForEach(model.entries) { entry in
                        NavigationLink {
                            PersonDetailView(entry: entry)
                                .environmentObject(theme)
                        } label: {
                            row(for: entry)
                        }
                        .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(AppTheme.color(for: .primaryUi01, theme: theme).ignoresSafeArea())
        .navigationTitle(L10n.peopleDirectoryTitle)
        .onAppear {
            model.load()
            Analytics.track(.peopleDirectoryShown, properties: ["person_count": model.entries.count])
        }
    }

    private func row(for entry: PersonDirectoryEntry) -> some View {
        HStack(spacing: 12) {
            monogram(for: entry.displayName)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(style: .body, weight: .medium)
                    .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                    .lineLimit(1)
                Text(entry.appearances.count == 1
                    ? L10n.peopleDirectoryEpisodeCountSingular
                    : L10n.peopleDirectoryEpisodeCountPlural("\(entry.appearances.count)"))
                    .font(style: .footnote)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func monogram(for name: String) -> some View {
        ZStack {
            Circle()
                .fill(AppTheme.color(for: .primaryUi05, theme: theme))
            Text(EpisodeCreditsViewModel.initials(for: name))
                .font(style: .footnote, weight: .semibold)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        }
        .frame(width: 40, height: 40)
    }
}
