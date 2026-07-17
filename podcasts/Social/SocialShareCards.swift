import SwiftUI
import PocketCastsServer
import PocketCastsUtils

/// Static shareable stat cards (Slice 3, docs/Social.md): a listening-stats
/// card and a heatmap card, rendered to images via the snapshot pipeline the
/// Share Profile card established. When the account has joined, cards carry
/// the @handle and the Profile Link to seed the referral loop; otherwise they
/// carry only the app name.
enum SocialShareCards {
    static let cardSize = CGSize(width: 340, height: 400)

    /// Renders the stats card and presents the system share sheet.
    @MainActor
    static func shareStatsCard(from presenter: UIViewController) {
        let card = StatsShareCardView(stats: .current(), footer: footer())
            .environmentObject(Theme.sharedTheme)
            .frame(width: cardSize.width, height: cardSize.height)
        Analytics.track(.socialStatsCardShared)
        present(card.snapshot(), from: presenter)
    }

    /// Renders the heatmap card and presents the system share sheet.
    @MainActor
    static func shareHeatmapCard(from presenter: UIViewController, heatmapModel: ListeningHeatmapViewModel) {
        let card = HeatmapShareCardView(viewModel: heatmapModel, footer: footer())
            .environmentObject(Theme.sharedTheme)
            .frame(width: cardSize.width, height: cardSize.height)
        Analytics.track(.socialHeatmapCardShared)
        present(card.snapshot(), from: presenter)
    }

    @MainActor
    private static func present(_ image: UIImage?, from presenter: UIViewController) {
        guard let image else { return }
        var items: [Any] = [image]
        if let handle = SocialIdentityStore.handle,
           let link = URL(string: "\(ServerConstants.Urls.api())u/\(handle)") {
            items.append(link)
        }
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = presenter.view
        presenter.present(activity, animated: true)
    }

    static func footer() -> String {
        if let handle = SocialIdentityStore.handle {
            return "@\(handle) · Pocket Casts"
        }
        return "Pocket Casts"
    }
}

/// The card's aggregate numbers, fixture-injectable for snapshots.
struct ListeningStatsFixture {
    let totalListened: TimeInterval
    let timeSaved: TimeInterval
    let since: Date?

    static func current() -> ListeningStatsFixture {
        let stats = StatsManager.shared
        let saved = stats.timeSavedDynamicSpeedInclusive() + stats.timeSavedVariableSpeedInclusive()
        return ListeningStatsFixture(totalListened: stats.totalListeningTimeInclusive(),
                                     timeSaved: saved,
                                     since: stats.statsStartDate())
    }
}

struct StatsShareCardView: View {
    @EnvironmentObject var theme: Theme
    let stats: ListeningStatsFixture
    let footer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "headphones")
                .font(.system(size: 34))
                .foregroundColor(AppTheme.color(for: .primaryIcon01, theme: theme))
            Spacer()
            statBlock(value: hoursText(stats.totalListened), label: L10n.socialCardHoursListened)
            statBlock(value: hoursText(stats.timeSaved), label: L10n.socialCardTimeSaved)
            if let since = stats.since {
                statBlock(value: since.formatted(.dateTime.month(.wide).year()), label: L10n.socialCardListeningSince)
            }
            Spacer()
            Text(footer)
                .font(.footnote.bold())
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(AppTheme.color(for: .primaryUi01, theme: theme))
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(label)
                .font(.footnote)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        }
    }

    private func hoursText(_ interval: TimeInterval) -> String {
        L10n.socialCardHoursValue(Int(interval / 3600))
    }
}

struct HeatmapShareCardView: View {
    @EnvironmentObject var theme: Theme
    @ObservedObject var viewModel: ListeningHeatmapViewModel
    let footer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.socialSectionHeatmap)
                .font(.title3.bold())
            ListeningHeatmapView(viewModel: viewModel)
            Spacer()
            Text(footer)
                .font(.footnote.bold())
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(AppTheme.color(for: .primaryUi01, theme: theme))
    }
}
