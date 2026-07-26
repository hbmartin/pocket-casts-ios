import PocketCastsDataModel
import PocketCastsUtils
import UIKit

extension FolderViewController {
    func setEditingOrder(_ editing: Bool) {
        guard isEditingOrder != editing else { return }
        isEditingOrder = editing

        if editing {
            enterEditMode()
        } else {
            exitEditMode()
        }
    }

    @objc func saveEditingTapped() {
        saveSortOrder()
        setEditingOrder(false)
    }

    func applyEditingTreatment(to cell: UICollectionViewCell) {
        if Settings.libraryType() == .list {
            addReorderHandle(to: cell)
        } else {
            cell.startEditingWiggle()
        }
    }

    func removeEditingTreatment(from cell: UICollectionViewCell) {
        removeReorderHandle(from: cell)
        cell.stopEditingWiggle()
    }

    // MARK: Mode transitions

    private func enterEditMode() {
        savedRightBarButtonItem = customRightBtn

        let saveButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(saveEditingTapped))
        setCustomRightBtn(saveButton, animated: true)

        mainGrid.dragInteractionEnabled = true
        mainGrid.allowsSelection = false
        setEnclosingTabBarHidden(true, animated: true)

        for cell in mainGrid.visibleCells {
            applyEditingTreatment(to: cell)
        }
    }

    private func exitEditMode() {
        mainGrid.dragInteractionEnabled = false
        mainGrid.allowsSelection = true
        setEnclosingTabBarHidden(false, animated: true)

        setCustomRightBtn(savedRightBarButtonItem, animated: true)
        savedRightBarButtonItem = nil

        for cell in mainGrid.visibleCells {
            removeEditingTreatment(from: cell)
        }

        if needsReloadAfterEditing {
            needsReloadAfterEditing = false
            reloadPodcasts()
        }
    }

    // MARK: Save

    func saveSortOrder() {
        // Podcast is a value type; mutate the VC-owned array in place before persisting.
        for index in podcasts.indices {
            podcasts[index].sortOrder = Int32(index)
        }

        DataManager.sharedManager.saveSortOrders(podcasts: podcasts)

        folder.syncModified = TimeFormatter.currentUTCTimeInMillis()
        folder.sortType = Int32(LibrarySort.Old.custom.rawValue)
        DataManager.sharedManager.save(folder: folder)
        NotificationCenter.postOnMainThread(FolderChanged(uuid: folder.uuid))
    }

    // MARK: Reorder handle (list)

    private func addReorderHandle(to cell: UICollectionViewCell) {
        (cell as? PodcastListCell)?.showsReorderHandle = true
    }

    private func removeReorderHandle(from cell: UICollectionViewCell) {
        (cell as? PodcastListCell)?.showsReorderHandle = false
    }
}

extension FolderViewController: UICollectionViewDragDelegate, UICollectionViewDropDelegate {
    // MARK: - UICollectionViewDragDelegate

    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard isEditingOrder, let podcast = podcastAt(indexPath) else {
            return []
        }
        let provider = NSItemProvider(object: podcast.uuid as NSString)
        let dragItem = UIDragItem(itemProvider: provider)
        dragItem.localObject = podcast
        return [dragItem]
    }

    func collectionView(_ collectionView: UICollectionView, dragSessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool {
        true
    }

    // MARK: - UICollectionViewDropDelegate

    func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
        session.localDragSession != nil
    }

    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        guard session.localDragSession != nil else {
            return UICollectionViewDropProposal(operation: .forbidden)
        }
        return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let dropItem = coordinator.items.first,
              let sourceIndexPath = dropItem.sourceIndexPath,
              podcasts.indices.contains(sourceIndexPath.item) else {
            return
        }
        let rawDestination = coordinator.destinationIndexPath?.item ?? podcasts.count - 1
        let clampedDestination = min(max(0, rawDestination), podcasts.count - 1)
        let destinationIndexPath = IndexPath(item: clampedDestination, section: 0)

        let moved = podcasts.remove(at: sourceIndexPath.item)
        podcasts.insert(moved, at: clampedDestination)

        // moveItem is illegal on a collection view driven by a diffable data
        // source; express the reorder as a snapshot change instead. The cells
        // already sit in their final spots (.immediate reorder cadence), so
        // the apply is not animated.
        var snapshot = dataSource.snapshot()
        snapshot.deleteItems([moved.uuid])
        if clampedDestination >= podcasts.count - 1 {
            snapshot.appendItems([moved.uuid], toSection: .podcasts)
        } else {
            snapshot.insertItems([moved.uuid], beforeItem: podcasts[clampedDestination + 1].uuid)
        }
        dataSource.apply(snapshot, animatingDifferences: false)
        coordinator.drop(dropItem.dragItem, toItemAt: destinationIndexPath)
    }
}
