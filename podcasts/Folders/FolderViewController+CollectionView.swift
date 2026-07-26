import Foundation
import PocketCastsDataModel
import PocketCastsUtils

extension FolderViewController: UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    private static let podcastCellId = "PodcastGridCell"
    private static let podcastListCellId = "PodcastListCell"

    func registerCells() {
        mainGrid.register(UINib(nibName: "PodcastGridCell", bundle: nil), forCellWithReuseIdentifier: FolderViewController.podcastCellId)
        mainGrid.register(UINib(nibName: "PodcastListCell", bundle: nil), forCellWithReuseIdentifier: FolderViewController.podcastListCellId)
    }

    func makeDataSource() -> UICollectionViewDiffableDataSource<FolderGridSection, String> {
        UICollectionViewDiffableDataSource<FolderGridSection, String>(collectionView: mainGrid) { [weak self] collectionView, indexPath, uuid in
            let libraryType = Settings.libraryType()
            let badgeType = Settings.podcastBadgeType()

            if libraryType == .list {
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FolderViewController.podcastListCellId, for: indexPath) as! PodcastListCell
                if let podcast = self?.podcastsByUuid[uuid] {
                    cell.populateFrom(podcast, badgeType: badgeType)
                }
                return cell
            }

            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FolderViewController.podcastCellId, for: indexPath) as! PodcastGridCell
            if let podcast = self?.podcastsByUuid[uuid] {
                cell.populateFrom(podcast: podcast, badgeType: badgeType, libraryType: libraryType)
            }
            return cell
        }
    }

    func podcastAt(_ indexPath: IndexPath) -> Podcast? {
        guard let uuid = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return podcastsByUuid[uuid]
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        // Keep the reorder-edit treatment in sync so reused/recycled cells stay correct.
        if isEditingOrder {
            applyEditingTreatment(to: cell)
        } else {
            removeEditingTreatment(from: cell)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)

        guard let podcast = podcastAt(indexPath) else { return }

        NavigationManager.sharedManager.navigateTo(NavigationManager.podcastPageKey, data: [NavigationManager.podcastKey: podcast])
    }

    // MARK: - Row Sizing

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        gridHelper.collectionView(collectionView, sizeForItemAt: indexPath, itemCount: podcasts.count)
    }

    func updateFlowLayoutSize() {
        guard let flowLayout = mainGrid.collectionViewLayout as? UICollectionViewFlowLayout else { return }

        flowLayout.invalidateLayout() // force the elements to get laid out again with the new size
    }
}
