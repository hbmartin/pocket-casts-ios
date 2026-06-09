import Combine
import Foundation
import SwiftUI

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

    func isUnconfiguredPreferred(_ id: String) -> Bool {
        // ok: pocketcasts.no-hardcoded-credential-placeholder-literal
        id.isMissingOrPlaceholderCredential
    }
}
