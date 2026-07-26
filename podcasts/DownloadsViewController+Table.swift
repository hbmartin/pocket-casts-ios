import PocketCastsDataModel
import PocketCastsUtils
import UIKit

extension DownloadsViewController: UITableViewDelegate {
    private static let cellId = "EpisodeCell"

    func registerTableCells() {
        downloadsTable.register(UINib(nibName: "EpisodeCell", bundle: nil), forCellReuseIdentifier: DownloadsViewController.cellId)
    }

    func makeDataSource() -> EditableDiffableDataSource<String, String> {
        let dataSource = EditableDiffableDataSource<String, String>(tableView: downloadsTable) { [weak self] tableView, indexPath, uuid in
            let cell = tableView.dequeueReusableCell(withIdentifier: DownloadsViewController.cellId, for: indexPath) as! EpisodeCell
            self?.populate(cell: cell, at: indexPath, uuid: uuid)
            return cell
        }
        dataSource.defaultRowAnimation = .fade
        return dataSource
    }

    private func populate(cell: EpisodeCell, at indexPath: IndexPath, uuid: String) {
        cell.delegate = self
        cell.playlist = .downloads
        if let listEpisode = episodesByUuid[uuid] {
            cell.populateFrom(episode: listEpisode.episode, tintColor: ThemeColor.primaryIcon01())
            cell.shouldShowSelect = isMultiSelectEnabled
            if isMultiSelectEnabled {
                cell.showTick = selectedEpisodesContains(uuid: uuid)
            }
        }

        cell.showsTopDivider = indexPath.row == 0
    }

    func registerLongPress() {
        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(tableLongPressed(_:)))
        downloadsTable.addGestureRecognizer(longPressRecognizer)
    }

    @objc private func tableLongPressed(_ sender: UILongPressGestureRecognizer) {
        if sender.state == .began {
            let touchPoint = sender.location(in: downloadsTable)
            guard let indexPath = downloadsTable.indexPathForRow(at: touchPoint) else { return }
            if isMultiSelectEnabled {
                longPressSelectOptions(
                    for: indexPath,
                    in: downloadsTable,
                    firstSection: 0,
                    lastSection: dataSource.snapshot().numberOfSections - 1,
                    statusBarStyle: preferredStatusBarStyle
                )
            } else {
                longPressMultiSelectIndexPath = indexPath
                isMultiSelectEnabled = true
            }
        }
    }

    // MARK: - Selection

    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        guard let listEpisode = listEpisodeAt(indexPath) else { return nil }

        guard downloadsTable.isEditing, !multiSelectGestureInProgress else { return indexPath }

        if selectedEpisodesContains(uuid: listEpisode.episode.uuid) {
            downloadsTable.delegate?.tableView?(downloadsTable, didDeselectRowAt: indexPath)
            return nil
        }
        return indexPath
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let listEpisode = listEpisodeAt(indexPath) else { return }
        let episode = listEpisode.episode

        if isMultiSelectEnabled {
            if !multiSelectGestureInProgress {
                // If the episode is already selected move to the end of the array
                selectedEpisodesRemove(uuid: listEpisode.episode.uuid)
            }

            if !multiSelectGestureInProgress || multiSelectGestureInProgress, !selectedEpisodesContains(uuid: episode.uuid) {
                selectedEpisodes.append(listEpisode)
                // the cell below is optional because cellForRow only returns a cell if it's visible, and we don't need to tick cells that don't exist
                if let cell = downloadsTable.cellForRow(at: indexPath) as? EpisodeCell? {
                    cell?.showTick = true
                }
            }
        } else {
            tableView.deselectRow(at: indexPath, animated: true)

            if episode.downloadFailed() {
                let optionsPicker = OptionsPicker(title: nil)
                let retryAction = OptionAction(label: L10n.retry, icon: nil, action: { [downloadManager = self.downloadManager] in
                    NetworkUtils.shared.downloadEpisodeRequested(autoDownloadStatus: .notSpecified, { later in
                        if later {
                            downloadManager.queueForLaterDownload(episodeUuid: episode.uuid, fireNotification: true, autoDownloadStatus: .notSpecified)
                        } else {
                            downloadManager.addToQueue(episodeUuid: episode.uuid)
                        }
                    }, disallowed: nil)
                })
                optionsPicker.addDescriptiveActions(title: L10n.downloadFailed, message: episode.readableErrorMessage(), icon: "option-alert", actions: [retryAction])
                optionsPicker.show(statusBarStyle: preferredStatusBarStyle)
            } else {
                let playOnTap = Settings.tapToPlay()
                Analytics.track(.episodeTapped, properties: ["source": AnalyticsSource.downloads, "will_play": playOnTap])

                if playOnTap {
                    AnalyticsPlaybackHelper.shared.currentSource = .downloads
                    PlaybackActionHelper.play(episode: episode, playlist: .downloads)
                    return
                }

                presentEpisodeDetails(for: episode)
            }
        }
    }

    /// Presents the episode detail sheet. Single source of truth for this screen —
    /// used by both row taps (when tap to play is off) and the Details swipe action.
    func presentEpisodeDetails(for episode: Episode) {
        guard let parentPodcast = episode.parentPodcast() else { return }

        let episodeController = EpisodeDetailViewController(episodeUuid: episode.uuid, podcast: parentPodcast, source: .downloads, playlist: .downloads)
        episodeController.modalPresentationStyle = .formSheet
        present(episodeController, animated: true, completion: nil)
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard isMultiSelectEnabled, let listEpisode = listEpisodeAt(indexPath) else { return }
        if let index = selectedEpisodes.firstIndex(where: { $0.episode.uuid == listEpisode.episode.uuid }) {
            selectedEpisodes.remove(at: index)
            if let cell = tableView.cellForRow(at: indexPath) as? EpisodeCell {
                cell.showTick = false
            }
        }
    }

    // MARK: - multi select support

    func tableView(_ tableView: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        Settings.multiSelectGestureEnabled()
    }

    func tableView(_ tableView: UITableView, didBeginMultipleSelectionInteractionAt indexPath: IndexPath) {
        isMultiSelectEnabled = true
        multiSelectGestureInProgress = true
    }

    func tableViewDidEndMultipleSelectionInteraction(_ tableView: UITableView) {
        multiSelectGestureInProgress = false
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let sectionHeader = DateHeadingView(frame: CGRect(x: 0, y: 0, width: tableView.frame.size.width, height: 45))
        sectionHeader.title = dataSource.sectionIdentifier(for: section) ?? ""

        return sectionHeader
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        80
    }

    // MARK: - Misc

    func episodeAtIndexPath(_ indexPath: IndexPath) -> Episode? {
        listEpisodeAt(indexPath)?.episode
    }

    func listEpisodeAt(_ indexPath: IndexPath) -> ListEpisode? {
        guard let uuid = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return episodesByUuid[uuid]
    }
}
