import Foundation
import PocketCastsDataModel
import PocketCastsUtils
import UIKit
import UserNotifications

/// Tells the user a narration finished while they were somewhere else.
///
/// Only fires when the app is not frontmost. Someone watching the library screen
/// can already see the progress bar reach the end, and a notification for
/// something they are looking at is noise. The fit is the actual use: start a
/// document, put the phone down, get told when there's something to listen to.
@MainActor
final class NarrationCompletionNotifier {
    static let categoryIdentifier = "READ_ALOUD_NARRATION"

    private let notificationCenter: UNUserNotificationCenter
    private let dataManager: DataManager
    /// Narrations that were still rendering when we last looked, so completion
    /// can be told apart from a row that was already finished.
    private var trackedNarrationUuids: Set<String> = []
    private let tokenBox = ObservationTokenBox()

    init(
        notificationCenter: UNUserNotificationCenter = .current(),
        dataManager: DataManager = .sharedManager
    ) {
        self.notificationCenter = notificationCenter
        self.dataManager = dataManager
    }

    func start() {
        guard tokenBox.token == nil else { return }
        tokenBox.token = NotificationCenter.default.addObserver(for: NarrationsChanged.self) { [weak self] _ in
            self?.checkForCompletions()
        }
        checkForCompletions()
    }

    private func checkForCompletions() {
        let narrations = dataManager.readAloud.allDocuments().flatMap {
            dataManager.readAloud.narrations(documentUuid: $0.uuid)
        }

        let active = Set(narrations.filter(\.isActive).map(\.uuid))
        let finished = narrations.filter {
            $0.narrationState == .completed && trackedNarrationUuids.contains($0.uuid)
        }
        trackedNarrationUuids = active

        // Nothing to say while the user is watching.
        guard UIApplication.shared.applicationState != .active else { return }

        for narration in finished {
            guard let document = dataManager.readAloud.document(uuid: narration.documentUuid) else { continue }
            notify(documentTitle: document.title, narrationUuid: narration.uuid)
        }
    }

    private func notify(documentTitle: String, narrationUuid: String) {
        // No permission prompt of our own: this piggybacks on whatever the user
        // already granted. An un-permitted `add` simply fails, which is the
        // right outcome — the episode is waiting in Files either way.
        let content = UNMutableNotificationContent()
        content.title = L10n.readAloudNotificationTitle
        content.body = L10n.readAloudNotificationBody(documentTitle)
        content.categoryIdentifier = NotificationsHelper.NotificationsCategory.deepLink.rawValue
        content.userInfo = ["destination_url": "thcast://files"]

        let request = UNNotificationRequest(
            identifier: "read-aloud-\(narrationUuid)",
            content: content,
            trigger: nil
        )
        let boxedRequest = PocketCastsUtils.UncheckedSendable(request)
        let center = notificationCenter
        Task {
            do {
                try await center.add(boxedRequest.value)
            } catch {
                FileLog.shared.addMessage("ReadAloud: could not post completion notification: \(error)")
            }
        }
    }
}
