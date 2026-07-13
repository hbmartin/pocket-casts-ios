import PocketCastsDataModel
import UIKit

class PodcastGridCell: UICollectionViewCell {

    @IBOutlet var shadowView: UIView!
    @IBOutlet var containerView: UIView!
    @IBOutlet var podcastImage: UIImageView!
    @IBOutlet var podcastName: UILabel!

    @IBOutlet var badgeView: GridBadgeView!
    @IBOutlet var supporterHeart: PodcastHeartView!

    private var podcastUuid: String?
    private var badgeType = BadgeType.off
    private var observationTokens = [NotificationCenter.ObservationToken]()

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        observationTokens.append(NotificationCenter.default.addObserver(for: PodcastColorsDownloaded.self) { [weak self] message in
            self?.podcastColorsLoaded(message)
        })
        observationTokens.append(NotificationCenter.default.addObserver(for: PodcastImageReCacheRequired.self) { [weak self] _ in
            self?.podcastImageCacheCleared()
        })
    }

    deinit {
        let tokens = observationTokens
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func setup() {
        containerView.layer.cornerRadius = 4
        containerView.layer.masksToBounds = true

        shadowView.layer.shadowColor = UIColor.black.cgColor
        shadowView.layer.shadowOffset = CGSize(width: 0, height: 1)
        shadowView.layer.shadowOpacity = 0.1
        shadowView.layer.shadowRadius = 2
        shadowView.layer.cornerRadius = 4
    }

    func populateFrom(podcast: Podcast, badgeType: BadgeType, libraryType: LibraryType) {
        self.badgeType = badgeType
        podcastUuid = podcast.uuid

        setup()

        setImage()
        setColors(podcast: podcast)

        podcastName.accessibilityLabel = podcast.title

        updateBadge(podcast: podcast, badgeType: badgeType, libraryType: libraryType)

        supporterHeart.isHidden = !podcast.isPaid
        if podcast.isPaid {
            supporterHeart.setPodcastColor(podcast: podcast)
        }
    }

    private func podcastImageCacheCleared() {
        setImage()
    }

    private func podcastColorsLoaded(_ message: PodcastColorsDownloaded) {
        guard let uuidLoaded = message.uuid else { return }

        if uuidLoaded == podcastUuid, let podcast = DataManager.sharedManager.findPodcast(uuid: uuidLoaded) {
            setColors(podcast: podcast)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        podcastUuid = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        shadowView.layer.shadowPath = UIBezierPath(rect: bounds).cgPath
    }

    private func setImage() {
        guard let podcastUuid else { return }

        ImageManager.sharedManager.loadImage(podcastUuid: podcastUuid, imageView: podcastImage, size: .grid, showPlaceHolder: false)
    }

    private func setColors(podcast: Podcast) {
        podcastName.text = podcast.title
        let bgColor = ColorManager.backgroundColorForPodcast(podcast)
        backgroundColor = .clear
        containerView.backgroundColor = bgColor
        podcastName.backgroundColor = bgColor

        if podcast.isPaid {
            supporterHeart.setPodcastColor(podcast: podcast)
        }
    }

    private func updateBadge(podcast: Podcast, badgeType: BadgeType, libraryType: LibraryType) {
        guard podcast.cachedUnreadCount > 0 else {
            badgeView.isHidden = true
            return
        }

        badgeView.populateFrom(podcast: podcast, badgeType: badgeType)
    }
}
