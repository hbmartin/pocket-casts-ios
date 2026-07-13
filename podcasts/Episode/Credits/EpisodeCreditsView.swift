import Kingfisher
import PocketCastsDataModel
import PocketCastsUtils
import SwiftUI

/// People-credits card on the episode detail screen: a horizontally scrolling
/// row of person chips (avatar or initials, name, role) sourced from
/// `<podcast:person>` metadata. Tapping a chip searches the catalog for that
/// person (plans/AI UX Improvements.md Phase 6). Self-hides when there are no
/// credits.
struct EpisodeCreditsView: View {
    @EnvironmentObject var theme: Theme
    @ObservedObject private var viewModel: EpisodeCreditsViewModel

    init(viewModel: EpisodeCreditsViewModel) {
        self.viewModel = viewModel
    }

    @ScaledMetric(relativeTo: .body) private var iconSize = 16
    @ScaledMetric(relativeTo: .body) private var avatarSize = 36

    var body: some View {
        if viewModel.persons.isEmpty {
            EmptyView()
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            chips
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.primaryUi02Active)
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 14)
        .onAppear {
            viewModel.cardAppeared()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "person.2")
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(theme.primaryIcon02)
                .accessibilityHidden(true)
            Text(L10n.episodeCreditsTitle)
                .font(size: 15, style: .body, weight: .semibold)
                .foregroundStyle(theme.primaryText01)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Person chips

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(viewModel.persons.enumerated()), id: \.offset) { _, person in
                    chip(person)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ person: Episode.Metadata.Person) -> some View {
        Button {
            viewModel.creditTapped(person)
        } label: {
            HStack(spacing: 8) {
                avatar(person)
                VStack(alignment: .leading, spacing: 1) {
                    Text(person.name)
                        .font(size: 14, style: .subheadline, weight: .semibold)
                        .foregroundStyle(theme.primaryText01)
                        .lineLimit(1)
                    if let role = person.role?.trim(), !role.isEmpty {
                        Text(role.localizedCapitalized)
                            .font(size: 11, style: .caption, weight: .regular)
                            .foregroundStyle(theme.primaryText02)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(theme.primaryUi05))
        }
        .buttonStyle(.plain)
        .accessibilityLabel([person.name, person.role].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(L10n.episodeCreditsFindMore)
    }

    @ViewBuilder
    private func avatar(_ person: Episode.Metadata.Person) -> some View {
        if let url = EpisodeCreditsViewModel.avatarURL(for: person) {
            KFImage(url)
                .placeholder { _ in
                    initialsAvatar(person)
                }
                .resizable()
                .scaledToFill()
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())
                .accessibilityHidden(true)
        } else {
            initialsAvatar(person)
        }
    }

    private func initialsAvatar(_ person: Episode.Metadata.Person) -> some View {
        ZStack {
            Circle()
                .fill(theme.primaryIcon02.opacity(0.2))
            Text(EpisodeCreditsViewModel.initials(for: person.name))
                .font(size: 13, style: .footnote, weight: .semibold)
                .foregroundStyle(theme.primaryText02)
        }
        .frame(width: avatarSize, height: avatarSize)
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Credits") {
    EpisodeCreditsView(
        viewModel: EpisodeCreditsViewModel(fixturePersons: [
            Episode.Metadata.Person(name: "Jane Doe", role: "host"),
            Episode.Metadata.Person(name: "Alex Example", role: "guest"),
            Episode.Metadata.Person(name: "Sam"),
        ])
    )
    .environmentObject(Theme(previewTheme: .light))
}

#Preview("Empty (self-hides)") {
    EpisodeCreditsView(
        viewModel: EpisodeCreditsViewModel(fixturePersons: [])
    )
    .environmentObject(Theme(previewTheme: .dark))
}
