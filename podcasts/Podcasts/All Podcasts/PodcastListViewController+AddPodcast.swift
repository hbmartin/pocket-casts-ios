import PocketCastsServer
import PocketCastsUtils
import UIKit

extension PodcastListViewController {
    func presentAddPodcastFlow() {
        let alert = UIAlertController(title: L10n.podcastAddAlertTitle, message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = L10n.podcastAddFeedUrlPlaceholder
            textField.keyboardType = .URL
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
            textField.returnKeyType = .go
        }

        alert.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.settingsOpml, style: .default) { [weak self] _ in
            self?.navigationController?.pushViewController(ImportExportViewController(), animated: true)
        })
        alert.addAction(UIAlertAction(title: L10n.podcastAddFeedUrlAction, style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let feedURLString = alert?.textFields?.first?.text,
                  !feedURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }

            self.addPodcast(feedURLString: feedURLString)
        })

        present(alert, animated: true)
    }

    private func addPodcast(feedURLString: String) {
        let feedURLStrings = normalizedFeedURLStrings(feedURLString)
        let loadingAlert = ShiftyLoadingAlert(title: L10n.podcastLoading)
        loadingAlert.showAlert(self, hasProgress: false) { [weak self] in
            self?.searchAndAddPodcast(feedURLStrings: feedURLStrings, loadingAlert: loadingAlert)
        }
    }

    private func searchAndAddPodcast(feedURLStrings: [String], index: Int = 0, loadingAlert: ShiftyLoadingAlert, lastErrorMessage: String? = nil) {
        guard index < feedURLStrings.count else {
            DispatchQueue.main.async { [weak self] in
                loadingAlert.hideAlert(false)
                if let self {
                    SJUIUtils.showAlert(title: L10n.error, message: lastErrorMessage ?? L10n.errorGeneralPodcastNotFound, from: self)
                }
            }
            return
        }

        MainServerHandler.shared.podcastSearch(searchTerm: feedURLStrings[index]) { [weak self] response in
            guard let self else {
                DispatchQueue.main.async {
                    loadingAlert.hideAlert(false)
                }
                return
            }

            guard let response, response.success(), let uuid = response.result?.podcast?.uuid else {
                self.searchAndAddPodcast(feedURLStrings: feedURLStrings,
                                         index: index + 1,
                                         loadingAlert: loadingAlert,
                                         lastErrorMessage: response?.message ?? lastErrorMessage)
                return
            }

            ServerPodcastManager.shared.addFromUuidWithRetries(podcastUuid: uuid, subscribe: false) { [weak self] success in
                DispatchQueue.main.async {
                    loadingAlert.hideAlert(false)
                    guard let self else { return }

                    if success {
                        NavigationManager.sharedManager.navigateTo(NavigationManager.podcastPageKey, data: [NavigationManager.podcastKey: uuid])
                    } else {
                        SJUIUtils.showAlert(title: L10n.error, message: L10n.errorGeneralPodcastNotFound, from: self)
                    }
                }
            }
        }
    }

    private func normalizedFeedURLStrings(_ value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        if trimmed.contains("://") {
            return [trimmed]
        }

        return ["https://\(trimmed)", "http://\(trimmed)"]
    }
}
