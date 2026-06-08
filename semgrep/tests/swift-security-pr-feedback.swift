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

    func exists(uuid: String) -> Bool {
        // ruleid: pocketcasts.podcast-exists-cache-lookup-must-be-atomic
        if cachedExists(uuid: uuid) {
            return true
        }

        let exists = findPodcast(uuid: uuid) != nil

        if exists {
            markExists(uuid: uuid)
        }

        return exists
    }

    private func cachedExists(uuid: String) -> Bool {
        checkedUuidsThatExist.contains(uuid)
    }

    private func findPodcast(uuid: String) -> String? {
        uuid
    }

    private func markExists(uuid: String) {
        checkedUuidsThatExist.insert(uuid)
    }
}

final class SafePodcastExistsHelper {
    private var checkedUuidsThatExist = Set<String>()
    private let lock = NSLock()

    func exists(uuid: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if checkedUuidsThatExist.contains(uuid) {
            return true
        }

        let exists = findPodcast(uuid: uuid) != nil

        if exists {
            checkedUuidsThatExist.insert(uuid)
        }

        return exists
    }

    private func findPodcast(uuid: String) -> String? {
        uuid
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
