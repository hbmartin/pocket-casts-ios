import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils
import UIKit

class UploadedStorageHeaderView: UIView {
    @IBOutlet var contentView: UIView!

    @IBOutlet var noFilesLabel: ThemeableLabel! {
        didSet {
            noFilesLabel.style = .primaryText02
            noFilesLabel.font = UIFont.font(ofSize: 12, weight: .semibold, scalingWith: .caption1)
            noFilesLabel.text = L10n.filesNotUploaded
        }
    }

    @IBOutlet var numFilesLabel: ThemeableLabel! {
        didSet {
            numFilesLabel.style = .primaryText02
            numFilesLabel.font = UIFont.font(ofSize: 12, weight: .semibold, scalingWith: .caption1)
        }
    }

    @IBOutlet var storageSizeLabel: ThemeableLabel! {
        didSet {
            storageSizeLabel.style = .primaryText02
            storageSizeLabel.font = UIFont.font(ofSize: 12, weight: .semibold, scalingWith: .caption1)
        }
    }

    @IBOutlet var plusView: ThemeableView! {
        didSet {
            plusView.style = .primaryUi02
        }
    }

    @IBOutlet var noPlusView: ThemeableView! {
        didSet {
            noPlusView.style = .primaryUi02
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(headerTapped))
            noPlusView.addGestureRecognizer(tapGesture)
        }
    }

    @IBOutlet var percentageLabel: ThemeableLabel! {
        didSet {
            percentageLabel.font = UIFont.font(ofSize: 12, weight: .semibold, scalingWith: .caption1)
        }
    }

    weak var controllerForPresenting: UIViewController?

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    private func commonInit() {
        Bundle.main.loadNibNamed("UploadedStorageHeaderView", owner: self, options: nil)
        addSubview(contentView)
        contentView.frame = bounds
        NotificationCenter.default.addObserver(self, selector: #selector(update), name: Constants.Notifications.themeChanged, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func headerTapped() {
        // Custom file storage is free now, so there is no upsell to present.
    }

    @objc func update() {
        plusView.isHidden = false
        noPlusView.isHidden = true

        if FeatureFlag.fileSync.enabled {
            let episodes = DataManager.sharedManager.allUserEpisodes(sortedBy: .newestToOldest)
            let totalBytes = episodes.reduce(Int64(0)) { $0 + $1.sizeInBytes }
            numFilesLabel.text = episodes.count == 1 ? L10n.profileSingleFile : L10n.profileNumberOfFiles(episodes.count.localized())
            storageSizeLabel.text = SizeFormatter.shared.defaultFormat(bytes: totalBytes)
            percentageLabel.text = L10n.fileSyncFolderIcloud
            percentageLabel.textColor = AppTheme.colorForStyle(.primaryText01)
            return
        }

        let maxStorage = Int64(ServerSettings.customStorageUserLimit())
        let usedStorage = Int64(ServerSettings.customStorageUsed())
        let numFiles = ServerSettings.customStorageNumFiles()

        let percentageUsed = maxStorage > 0 ? Double(usedStorage) / Double(maxStorage) : 0
        numFilesLabel.text = numFiles == 1 ? L10n.profileSingleFile : L10n.profileNumberOfFiles(numFiles.localized())
        storageSizeLabel.text = "\(SizeFormatter.shared.defaultFormat(bytes: usedStorage))/ \(SizeFormatter.shared.defaultFormat(bytes: maxStorage))"
        percentageLabel.text = L10n.profilePercentFull(percentageUsed.localized(.percent))

        if percentageUsed >= 0.99 {
            percentageLabel.textColor = AppTheme.colorForStyle(.support05)
        } else if percentageUsed >= 0.90 {
            percentageLabel.textColor = AppTheme.colorForStyle(.support08)
        } else {
            percentageLabel.textColor = AppTheme.colorForStyle(.primaryText01)
        }
    }
}
