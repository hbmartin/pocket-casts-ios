import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Drives the people-credits card on the episode detail screen
/// (plans/AI UX Improvements.md Phase 6). The persons come from
/// `Episode.Metadata.persons` — already loaded by the detail screen, which only
/// attaches the card when the list is non-empty — so this model just renders
/// and reports taps.
class EpisodeCreditsViewModel: ObservableObject {
    let persons: [Episode.Metadata.Person]
    let episodeUuid: String
    let podcastUuid: String

    /// Launches a catalog search for the tapped person's name; injected by the
    /// hosting controller so the card stays presentation-agnostic.
    private let searchHandler: (String) -> Void
    private var hasTrackedShown: Bool

    init(
        persons: [Episode.Metadata.Person],
        episodeUuid: String,
        podcastUuid: String,
        searchHandler: @escaping (String) -> Void
    ) {
        self.persons = persons
        self.episodeUuid = episodeUuid
        self.podcastUuid = podcastUuid
        self.searchHandler = searchHandler
        self.hasTrackedShown = false
    }

    /// Fixture initializer for previews and snapshot tests: taps are no-ops and
    /// `cardAppeared()` never tracks anything.
    init(fixturePersons: [Episode.Metadata.Person]) {
        self.persons = fixturePersons
        self.episodeUuid = ""
        self.podcastUuid = ""
        self.searchHandler = { _ in }
        self.hasTrackedShown = true
    }

    // MARK: - Lifecycle

    func cardAppeared() {
        guard !hasTrackedShown else { return }
        hasTrackedShown = true
        track(.episodeDetailCreditsShown, extraProperties: ["count": persons.count])
    }

    func creditTapped(_ person: Episode.Metadata.Person) {
        track(.episodeDetailCreditTapped, extraProperties: ["role": person.role ?? "unknown"])
        searchHandler(person.name)
    }

    // MARK: - Presentation helpers

    /// Up-to-two-letter monogram for the avatar fallback when a person has no
    /// (usable) image URL.
    static func initials(for name: String) -> String {
        name.split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .localizedUppercase
    }

    /// Only http(s) avatar images are fetched — same posture as chapter links.
    static func avatarURL(for person: Episode.Metadata.Person) -> URL? {
        guard let img = person.img,
              let url = URL(string: img),
              let scheme = url.scheme,
              scheme.caseInsensitiveCompare("http") == .orderedSame || scheme.caseInsensitiveCompare("https") == .orderedSame
        else {
            return nil
        }
        return url
    }

    // MARK: - Analytics

    private func track(_ event: AnalyticsEvent, extraProperties: [String: Sendable] = [:]) {
        var properties: [String: Sendable] = [
            "episode_uuid": episodeUuid,
            "podcast_uuid": podcastUuid
        ]
        properties.merge(extraProperties) { current, _ in current }
        Analytics.track(event, properties: properties)
    }
}
