import PocketCastsDataModel
import PocketCastsUtils
import UIKit

class UploadedStorageHeaderView: UIView {
    @IBOutlet var contentView: UIView!

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

    @IBOutlet var percentageLabel: ThemeableLabel! {
        didSet {
            percentageLabel.font = UIFont.font(ofSize: 12, weight: .semibold, scalingWith: .caption1)
        }
    }

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

    @objc func update() {
        plusView.isHidden = false

        let episodes = DataManager.sharedManager.allUserEpisodes(sortedBy: .newestToOldest)
        let totalBytes = episodes.reduce(Int64(0)) { $0 + $1.sizeInBytes }
        numFilesLabel.text = episodes.count == 1 ? L10n.profileSingleFile : L10n.profileNumberOfFiles(episodes.count.localized())
        storageSizeLabel.text = SizeFormatter.shared.defaultFormat(bytes: totalBytes)
        percentageLabel.text = FeatureFlag.fileSync.enabled ? L10n.fileSyncFolderIcloud : nil
        percentageLabel.textColor = AppTheme.colorForStyle(.primaryText01)
    }
}
