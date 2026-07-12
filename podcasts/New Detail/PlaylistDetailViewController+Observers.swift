import PocketCastsServer
import PocketCastsUtils

extension PlaylistDetailViewController {
    struct PlaylistReloadScope: OptionSet {
        let rawValue: Int

        static let episodes = PlaylistReloadScope(rawValue: 1 << 0)
        static let playlist = PlaylistReloadScope(rawValue: 1 << 1)
    }

    func addObservers() {
        addCustomObserver(ServerNotifications.podcastsRefreshed, selector: #selector(refreshEpisodesFromNotification))
        addCustomObserver(OpmlImportCompleted.self) { [weak self] _ in
            self?.reloader.request(.episodes)
        }
        addCustomObserver(EpisodeDownloaded.self) { [weak self] _ in
            self?.reloader.request(.episodes)
        }
        addCustomObserver(Constants.Notifications.playbackTrackChanged, selector: #selector(refreshEpisodesFromNotification))
        addCustomObserver(Constants.Notifications.playbackEnded, selector: #selector(refreshEpisodesFromNotification))
        addCustomObserver(Constants.Notifications.playbackFailed, selector: #selector(refreshEpisodesFromNotification))
        addCustomObserver(PlaylistChanged.self) { [weak self] _ in
            self?.reloader.request(.playlist)
        }
        addCustomObserver(EpisodePlayStatusChanged.self) { [weak self] _ in
            self?.reloader.request(.episodes)
        }
        addCustomObserver(EpisodeArchiveStatusChanged.self) { [weak self] _ in
            self?.reloader.request(.episodes)
        }
        addCustomObserver(EpisodeStarredChanged.self) { [weak self] _ in
            self?.reloader.request(.episodes)
        }
        addCustomObserver(EpisodeDownloadStatusChanged.self) { [weak self] _ in
            self?.reloader.request(.episodes)
        }
        addCustomObserver(ManyEpisodesChanged.self) { [weak self] _ in
            self?.reloader.request(.episodes)
        }
        addCustomObserver(UIResponder.keyboardWillShowNotification, selector: #selector(keyboardWillShow(_:)))
        addCustomObserver(UIResponder.keyboardWillHideNotification, selector: #selector(keyboardWillHide(_:)))
    }

    @objc func keyboardWillShow(_ notification: Notification) {
        adjustTextViewForKeyboard(notification: notification, show: true)
    }

    @objc func keyboardWillHide(_ notification: Notification) {
        adjustTextViewForKeyboard(notification: notification, show: false)
    }

    private func adjustTextViewForKeyboard(notification: Notification, show: Bool) {
        guard let userInfo = notification.userInfo,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }

        let keyboardHeight = keyboardFrame.height
        keyBoardHeight = (show ? keyboardHeight - (view.distanceFromBottom() ?? 0) : 0)
    }
}
