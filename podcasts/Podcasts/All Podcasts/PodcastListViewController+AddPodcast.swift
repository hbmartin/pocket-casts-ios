import PocketCastsServer
import PocketCastsUtils
import UIKit

extension PodcastListViewController {
    func presentAddPodcastFlow() {
        let alert = UIAlertController(title: L10n.podcastGridNoPodcastsTitle, message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "https://example.com/feed.xml"
            textField.keyboardType = .URL
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
            textField.returnKeyType = .go
        }

        alert.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.settingsOpml, style: .default) { [weak self] _ in
            self?.navigationController?.pushViewController(ImportExportViewController(), animated: true)
        })
        alert.addAction(UIAlertAction(title: "Add Feed URL", style: .default) { [weak self, weak alert] _ in
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
        let normalizedURLString = normalizedFeedURLString(feedURLString)
        let loadingAlert = ShiftyLoadingAlert(title: L10n.podcastLoading)
        loadingAlert.showAlert(self, hasProgress: false) {
            MainServerHandler.shared.podcastSearch(searchTerm: normalizedURLString) { [weak self] response in
                guard let self else { return }
                guard let uuid = response?.result?.podcast?.uuid else {
                    DispatchQueue.main.async {
                        loadingAlert.hideAlert(false)
                        SJUIUtils.showAlert(title: L10n.error, message: L10n.errorGeneralPodcastNotFound, from: self)
                    }
                    return
                }

                ServerPodcastManager.shared.addFromUuidWithRetries(podcastUuid: uuid, subscribe: false) { success in
                    DispatchQueue.main.async {
                        loadingAlert.hideAlert(false)
                        if success {
                            NavigationManager.sharedManager.navigateTo(NavigationManager.podcastPageKey, data: [NavigationManager.podcastKey: uuid])
                        } else {
                            SJUIUtils.showAlert(title: L10n.error, message: L10n.errorGeneralPodcastNotFound, from: self)
                        }
                    }
                }
            }
        }
    }

    private func normalizedFeedURLString(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }

        return "https://\(trimmed)"
    }
}
