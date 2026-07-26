import PocketCastsDataModel
import UIKit

extension UploadedViewController: UITableViewDelegate {
    func registerCells() {
        uploadsTable.register(UINib(nibName: "EpisodeCell", bundle: nil), forCellReuseIdentifier: "EpisodeCell")
    }

    func registerLongPress() {
        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(tableLongPressed(_:)))
        uploadsTable.addGestureRecognizer(longPressRecognizer)
    }

    // MARK: TableView Datasource

    func makeDataSource() -> EditableDiffableDataSource<UploadedFilesSection, String> {
        let dataSource = EditableDiffableDataSource<UploadedFilesSection, String>(tableView: uploadsTable) { [weak self] tableView, indexPath, uuid in
            let cell = tableView.dequeueReusableCell(withIdentifier: "EpisodeCell", for: indexPath) as! EpisodeCell
            self?.populate(cell: cell, uuid: uuid)
            return cell
        }
        dataSource.defaultRowAnimation = .fade
        return dataSource
    }

    private func populate(cell: EpisodeCell, uuid: String) {
        cell.hidesArtwork = false
        cell.playlist = .files
        cell.delegate = self
        guard let userEpisode = episodesByUuid[uuid] else { return }
        let episode: BaseEpisode = userEpisode as BaseEpisode
        cell.populateFrom(episode: episode, tintColor: ThemeColor.primaryIcon01(), podcastUuid: episode.parentIdentifier())
        cell.shouldShowSelect = isMultiSelectEnabled
        if isMultiSelectEnabled {
            cell.showTick = selectedEpisodesContains(uuid: uuid)
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let sectionIdentifier = dataSource.sectionIdentifier(for: section) else { return nil }

        switch sectionIdentifier {
        case .root:
            return headerView
        case .group(let name):
            let sectionHeader = DateHeadingView(frame: CGRect(x: 0, y: 0, width: tableView.frame.size.width, height: 45))
            sectionHeader.title = name
            return sectionHeader
        }
    }

    // MARK: - Selection

    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        guard uploadsTable.isEditing, !multiSelectGestureInProgress else { return indexPath }

        if let episode = episodeAt(indexPath), selectedEpisodesContains(uuid: episode.uuid) {
            uploadsTable.delegate?.tableView?(uploadsTable, didDeselectRowAt: indexPath)
            return nil
        }
        return indexPath
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if isMultiSelectEnabled {
            guard let userEpisode = episodeAt(indexPath) else { return }

            if !multiSelectGestureInProgress {
                // If the episode is already selected move to the end of the array
                selectedEpisodesRemove(uuid: userEpisode.uuid)
            }

            if !multiSelectGestureInProgress || multiSelectGestureInProgress, !selectedEpisodesContains(uuid: userEpisode.uuid) {
                selectedEpisodes.append(userEpisode)
                // the cell below is optional because cellForRow only returns a cell if it's visible, and we don't need to tick cells that don't exist
                if let cell = uploadsTable.cellForRow(at: indexPath) as? EpisodeCell? {
                    cell?.showTick = true
                }
            }
        } else {
            tableView.deselectRow(at: indexPath, animated: true)
            guard let episode = episodeAt(indexPath) else { return }

            let playOnTap = Settings.tapToPlay()
            Analytics.track(.episodeTapped, properties: ["source": AnalyticsSource.files, "will_play": playOnTap])

            if playOnTap {
                AnalyticsPlaybackHelper.shared.currentSource = .files
                PlaybackActionHelper.play(episode: episode, playlist: .files)
                return
            }

            presentEpisodeDetails(for: episode)
        }
    }

    /// Presents the episode detail sheet. Single source of truth for this screen —
    /// used by both row taps (when tap to play is off) and the Details swipe action.
    func presentEpisodeDetails(for episode: UserEpisode) {
        userEpisodeDetailVC = UserEpisodeDetailViewController(episode: episode)
        userEpisodeDetailVC?.playlist = .files
        userEpisodeDetailVC?.delegate = self
        userEpisodeDetailVC?.present(from: self)
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard isMultiSelectEnabled, let userEpisode = episodeAt(indexPath) else { return }
        if let index = selectedEpisodes.firstIndex(where: { $0.uuid == userEpisode.uuid }) {
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

    // MARK: - Long Press Gesture

    @objc private func tableLongPressed(_ sender: UILongPressGestureRecognizer) {
        if sender.state == .began {
            let touchPoint = sender.location(in: uploadsTable)
            guard let indexPath = uploadsTable.indexPathForRow(at: touchPoint) else { return }
            if isMultiSelectEnabled {
                longPressSelectOptions(
                    for: indexPath,
                    in: uploadsTable,
                    statusBarStyle: preferredStatusBarStyle
                )
            } else {
                longPressMultiSelectIndexPath = indexPath
                isMultiSelectEnabled = true
            }
        }
    }
}
