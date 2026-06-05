import UIKit
import SwiftUI
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils

class FoldersCoordinator: NSObject {
    private let startingTime = Date.now

    private let navigationManager: NavigationManager
    private let dataManager: DataManager
    private let suggestedFoldersModel: SuggestedFoldersModel

    private enum Constants {
        static let minimumNumberOfPodcasts: Int = 7
        static let intervalBetweenUpsell: TimeInterval = 7.days
        static let maxUpsellDisplays: Int = 2
        static let intervalAfterStartup: TimeInterval = 10.seconds
    }

    init(navigationManager: NavigationManager = .sharedManager, dataManager: DataManager = .sharedManager) {
        self.navigationManager = navigationManager
        self.dataManager = dataManager
        self.suggestedFoldersModel = SuggestedFoldersModel()
        super.init()
        Task {
            await suggestedFoldersModel.load()
        }
    }

    func startFolderCreationFlow(from vc: UIViewController) {
        if FeatureFlag.suggestedFolders.enabled,
           dataManager.allPodcasts(includeUnsubscribed: false, reloadFromDatabase: false).count > Constants.minimumNumberOfPodcasts,
           suggestedFoldersModel.loadingState == .loaded,
           didPodcastsChanged() {
            suggestedFolderCreationFlow(from: vc, source: .podcastsList)
        } else {
            manualFolderCreationFlow(from: vc)
        }
        AnalyticsHelper.folderCreated()
        Analytics.track(.podcastsListFolderButtonTapped)
    }

    func showSuggestedFolders(from vc: UIViewController, source: AnalyticsSource = .notifications) {
        guard FeatureFlag.suggestedFolders.enabled,
              dataManager.allPodcasts(includeUnsubscribed: false, reloadFromDatabase: false).count > Constants.minimumNumberOfPodcasts else {
            return
        }
        suggestedFolderCreationFlow(from: vc, source: source)
    }

    func showUpsellIfNeeded(from vc: UIViewController) {
        // Suggested folders are free, so there is no background upsell flow.
    }

    private func manualFolderCreationFlow(from vc: UIViewController) {
        let creatFolderView = CreateFolderView { [weak vc, weak self] folderUuid in
            guard let self else { return }
            if let folderUuid, let folder = dataManager.findFolder(uuid: folderUuid) {
                vc?.dismiss(animated: true, completion: { [weak self] in
                    self?.navigationManager.navigateTo(NavigationManager.folderPageKey, data: [NavigationManager.folderKey: folder])
                })
            } else {
                vc?.dismiss(animated: true, completion: nil)
            }
        }
        let hostingController = PCHostingController(rootView: creatFolderView.environmentObject(Theme.sharedTheme))

        vc.present(hostingController, animated: true, completion: nil)
    }

    private func suggestedFolderCreationFlow(from vc: UIViewController, source: AnalyticsSource) {
        let suggestedFoldersView = SuggestedFoldersView(model: suggestedFoldersModel, source: source) { [weak vc, weak self] result in
            guard let self, let vc else { return }

            switch result {
            case .dismiss:
                vc.dismiss(animated: true, completion: nil)
            case .applySuggestedFolders(let folders):
                vc.dismiss(animated: true, completion: nil)
                applySuggestedFolders(folders)
            case .createdManualFolder(let folderUuid):
                guard let folder = dataManager.findFolder(uuid: folderUuid) else {
                    vc.dismiss(animated: true, completion: nil)
                    return
                }
                vc.dismiss(animated: true, completion: { [weak self] in
                    self?.navigationManager.navigateTo(NavigationManager.folderPageKey, data: [NavigationManager.folderKey: folder])
                })
            }
        }
        let hostingController = UIHostingController(rootView: suggestedFoldersView.environmentObject(Theme.sharedTheme))
        vc.present(hostingController, animated: true, completion: nil)
        hostingController.sheetPresentationController?.delegate = self
    }

    private func applySuggestedFolders(_ suggestedFolders: [SuggestedFolder]) {
        saveLastUuidsUsed()
        DataManager.sharedManager.deleteAllFoldersAndMarkSync()
        for suggestedFolder in suggestedFolders {
            let folder = makeFolder(from: suggestedFolder)
            dataManager.bulkSetFolderUuid(folderUuid: folder.uuid, podcastUuids: suggestedFolder.podcastUuids)
        }
        NotificationCenter.postOnMainThread(notification: ServerNotifications.podcastsRefreshed, object: nil)
    }

    private var currentPodcastsHash: String {
        let uuids = dataManager.allPodcastsOrderedByAddedDate().map { $0.uuid }.sorted()
        let md5 = uuids.joined().md5
        return md5
    }

    private func saveLastUuidsUsed() {
        Settings.suggestedFoldersLastPodcastsUsed = currentPodcastsHash
    }

    private func didPodcastsChanged() -> Bool {
        return Settings.suggestedFoldersLastPodcastsUsed != currentPodcastsHash
    }

    private func makeFolder(from suggestedFolder: SuggestedFolder) -> Folder {
        let folder = Folder()
        folder.name = suggestedFolder.name
        folder.color = suggestedFolder.color
        folder.addedDate = Date()
        folder.syncModified = TimeFormatter.currentUTCTimeInMillis()
        folder.sortOrder = ServerPodcastManager.shared.lowestSortOrderForHomeGrid() - 1

        // the sort type for newly created folders defaults to the same thing the home grid is set to
        folder.sortType = Int32(Settings.homeFolderSortOrder().old.rawValue)
        dataManager.save(folder: folder)
        return folder
    }
}

extension FoldersCoordinator: UISheetPresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        Analytics.track(.suggestedFoldersPageDismissed, properties: [:])
    }
}
