import Combine
import Foundation
import SwiftUI
import UIKit

struct UnsafeStoriesView: View {
    @State private var timerSubscription: Cancellable?

    // ruleid: pocketcasts.swiftui-connectable-timer-publisher-must-be-state
    private let timer = Timer.publish(every: 0.02, on: .main, in: .common)

    var body: some View {
        Text("Unsafe")
            .onReceive(timer) { _ in }
    }
}

struct SafeStoriesView: View {
    @State private var timerSubscription: Cancellable?

    // ok: pocketcasts.swiftui-connectable-timer-publisher-must-be-state
    @State private var timer = Timer.publish(every: 0.02, on: .main, in: .common)

    var body: some View {
        Text("Safe")
            .onReceive(timer) { _ in }
    }
}

final class UnsafePodcastExistsHelper {
    private var checkedUuidsThatExist = Set<String>()
    private let lock = NSLock()

    func exists(uuid: String) -> Bool {
        // ruleid: pocketcasts.no-datamanager-query-while-holding-nslock
        lock.lock()
        defer { lock.unlock() }

        if checkedUuidsThatExist.contains(uuid) {
            return true
        }

        let exists = DataManager.sharedManager.findPodcast(uuid: uuid, includeUnsubscribed: true) != nil

        if exists {
            checkedUuidsThatExist.insert(uuid)
        }

        return exists
    }
}

final class UnsafeWithLockPodcastExistsHelper {
    private let lock = NSLock()

    func exists(uuid: String) -> Bool {
        // ruleid: pocketcasts.no-datamanager-query-while-holding-nslock
        lock.withLock {
            DataManager.sharedManager.findPodcast(uuid: uuid, includeUnsubscribed: true) != nil
        }
    }
}

final class SafePodcastExistsHelper {
    private var checkedUuidsThatExist = Set<String>()
    private let lock = NSLock()

    private func cachedExists(uuid: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return checkedUuidsThatExist.contains(uuid)
    }

    func exists(uuid: String) -> Bool {
        if cachedExists(uuid: uuid) {
            return true
        }

        // ok: pocketcasts.no-datamanager-query-while-holding-nslock
        let exists = DataManager.sharedManager.findPodcast(uuid: uuid, includeUnsubscribed: true) != nil

        if exists {
            markExists(uuid: uuid)
        }

        return exists
    }

    private func markExists(uuid: String) {
        lock.lock()
        defer { lock.unlock() }

        checkedUuidsThatExist.insert(uuid)
    }
}

final class UnsafeEpisodeListHeaderView {
    private var webURL: URL?

    @objc private func linkTapped() {
        guard let webURL else { return }

        // ruleid: pocketcasts.external-link-tap-requires-allowlist-guard
        URLHelper.open(
            webURL,
            context: .externalContent,
            options: .init()
        )
    }
}

final class SafeEpisodeListHeaderView {
    private var webURL: URL?

    @objc private func linkTapped() {
        guard let webURL, URLHelper.isAllowedExternalContentLink(webURL) else { return }

        // ok: pocketcasts.external-link-tap-requires-allowlist-guard
        URLHelper.open(
            webURL,
            context: .externalContent,
            options: .init()
        )
    }
}

final class UnsafeDatabaseSchemaResetHelper {
    // ruleid: pocketcasts.no-destructive-database-schema-reset
    private class func dropExistingSchema(db: PCDatabase) throws {
        try db.executeUpdate("DROP TABLE IF EXISTS SJPodcast;", values: nil)
    }
}

final class UnsafeSQLiteMasterBulkDropHelper {
    private class func resetTables(db: PCDatabase) throws {
        // ruleid: pocketcasts.no-destructive-database-schema-reset
        let resultSet = try db.executeQuery("""
            SELECT name FROM sqlite_master
            WHERE type = 'table'
        """, values: nil)

        while resultSet.next() {
            guard let table = resultSet.string(forColumn: "name") else { continue }
            try db.executeUpdate("DROP TABLE IF EXISTS \(table);", values: nil)
        }
    }
}

final class SafeDatabaseSchemaSetupHelper {
    private class func createCurrentSchema(db: PCDatabase) throws {
        // ok: pocketcasts.no-destructive-database-schema-reset
        try db.executeUpdate("CREATE TABLE SJPodcast (id INTEGER PRIMARY KEY);", values: nil)
    }
}

final class CredentialPlaceholderRegressionHelper {
    func isUnconfigured(_ id: String) -> Bool {
        // ruleid: pocketcasts.no-hardcoded-credential-placeholder-literal
        id == "%{telemetry_deck_app_id}"
    }

    func isUnconfiguredHyphenated(_ id: String) -> Bool {
        // ruleid: pocketcasts.no-hardcoded-credential-placeholder-literal
        id == "%{telemetry-deck-app-id}"
    }

    func isUnconfiguredPreferred(_ id: String) -> Bool {
        // ok: pocketcasts.no-hardcoded-credential-placeholder-literal
        id.isMissingOrPlaceholderCredential
    }
}

final class UnsafeNativeEmptyStateActionViewController {
    func refreshContentUnavailable() {
        _ = ContentUnavailableConfiguration.nativeEmptyState(
            title: "Empty",
            message: nil,
            image: nil,
            // ruleid: pocketcasts.native-empty-state-action-weak-self
            action: .init(title: "Add") {
                self.addPodcastsTapped(self)
            }
        )
    }

    func addPodcastsTapped(_ sender: Any) {}
}

final class SafeNativeEmptyStateActionViewController {
    func refreshContentUnavailable() {
        _ = ContentUnavailableConfiguration.nativeEmptyState(
            title: "Empty",
            message: nil,
            image: nil,
            action: .init(title: "Add") { [weak self] in
                // ok: pocketcasts.native-empty-state-action-weak-self
                guard let self else { return }
                self.addPodcastsTapped(self)
            }
        )
    }

    func addPodcastsTapped(_ sender: Any) {}
}

final class UnsafeListeningHistoryEmptyStateController {
    private var episodes = [String]()
    private var contentUnavailableConfiguration: UIContentConfiguration?

    private func refreshContentUnavailable() {
        var config: UIContentConfiguration?

        if episodes.isEmpty {
            config = ContentUnavailableConfiguration.empty()
            // ruleid: pocketcasts.content-unavailable-assigned-inside-empty-branch
            self.contentUnavailableConfiguration = config
        }
    }
}

final class SafeListeningHistoryEmptyStateController {
    private var episodes = [String]()
    private var contentUnavailableConfiguration: UIContentConfiguration?

    private func refreshContentUnavailable() {
        var config: UIContentConfiguration?

        if episodes.isEmpty {
            config = ContentUnavailableConfiguration.empty()
        }

        // ok: pocketcasts.content-unavailable-assigned-inside-empty-branch
        self.contentUnavailableConfiguration = config
    }
}

final class UnsafePlaylistCellViewModelFacadeBypass {
    private let episodesDataManager = EpisodesDataManager()
    private let playlist = EpisodeFilter()

    func loadListEpisodes() {
        // ruleid: pocketcasts.playlist-cell-bypass-datamanager-facade
        episodesDataManager.playlistFirstDistinctEpisodes(for: playlist, shouldShowArchived: true)
    }
}

final class SafePlaylistCellViewModelFacadeUse {
    private let dataManager = DataManager.sharedManager
    private let playlist = EpisodeFilter()

    func loadListEpisodes() {
        // ok: pocketcasts.playlist-cell-bypass-datamanager-facade
        dataManager.playlistFirstDistinctEpisodes(for: playlist, shouldShowArchived: true)
    }
}

final class UnsafeClipExportToast {
    func show(error: Error) {
        // ruleid: pocketcasts.share-button-localized-clip-export-failure
        Toast.show("Failed clip export: \(error.localizedDescription)")
    }
}

final class SafeClipExportToast {
    func show(error: Error) {
        let format = L10n.localizedFormat("sharing_clip_export_failed", "Localizable", "Failed clip export: %@")
        // ok: pocketcasts.share-button-localized-clip-export-failure
        Toast.show(String(format: format, locale: Locale.current, error.localizedDescription))
    }
}

struct UnsafeNativeEmptyStateThemeColor {
    static func nativeEmptyState(title: String, message: String?, image: UIImage?) -> UIContentConfiguration {
        let themeType = Theme.sharedTheme.activeTheme
        var configuration = UIKit.UIContentUnavailableConfiguration.empty()
        // ruleid: pocketcasts.native-empty-state-themecolor-bypass
        configuration.imageProperties.tintColor = ThemeColor.primaryIcon01(for: themeType)
        return configuration
    }
}

struct SafeNativeEmptyStateThemeColor {
    static func nativeEmptyState(title: String, message: String?, image: UIImage?) -> UIContentConfiguration {
        let theme = Theme.sharedTheme
        var configuration = UIKit.UIContentUnavailableConfiguration.empty()
        // ok: pocketcasts.native-empty-state-themecolor-bypass
        configuration.imageProperties.tintColor = UIColor(AppTheme.color(for: .primaryIcon01, theme: theme))
        return configuration
    }
}
