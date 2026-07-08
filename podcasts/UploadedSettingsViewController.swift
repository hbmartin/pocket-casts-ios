import PocketCastsServer
import PocketCastsUtils
import UIKit

class UploadedSettingsViewController: PCViewController, UITableViewDelegate, UITableViewDataSource {
    private let switchCellId = "SwitchCell"
    private enum TableSections: Int { case autoSync, autoAddToUpNext, afterPlaying, onlyOnWifi }
    private enum TableRows: Int { case autoDownload, autoUpload, autoAddToUpNext, removeFileAfterPlaying, removeFromCloudAfterPlaying, onlyOnWifi }

    @IBOutlet var settingsTable: UITableView! {
        didSet {
            settingsTable.register(UINib(nibName: "SwitchCell", bundle: nil), forCellReuseIdentifier: switchCellId)

            settingsTable.rowHeight = UITableView.automaticDimension
            settingsTable.estimatedRowHeight = UITableView.automaticDimension
            settingsTable.sectionHeaderHeight = UITableView.automaticDimension
            settingsTable.estimatedSectionHeaderHeight = Constants.Values.tableSectionHeaderHeight
            settingsTable.sectionFooterHeight = UITableView.automaticDimension
            settingsTable.estimatedSectionFooterHeight = Constants.Values.tableSectionHeaderHeight
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        AppTheme.defaultStatusBarStyle()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.settingsFiles
        insetAdjuster.setupInsetAdjustmentsForMiniPlayer(scrollView: settingsTable)
    }

    private func tableSections() -> [TableSections] {
        if FeatureFlag.fileSync.enabled {
            // Folder-sync model: server auto-upload/download and
            // cloud-delete settings don't apply; the folder is the library
            // and removing a file after playing is cache eviction.
            return [.autoAddToUpNext, .afterPlaying]
        }
        return [.autoAddToUpNext, .afterPlaying, .autoSync, .onlyOnWifi]
    }

    private func tableRows() -> [[TableRows]] {
        if FeatureFlag.fileSync.enabled {
            return [[.autoAddToUpNext], [.removeFileAfterPlaying]]
        }
        return [[.autoAddToUpNext], [.removeFileAfterPlaying, .removeFromCloudAfterPlaying], [.autoUpload, .autoDownload], [.onlyOnWifi]]
    }

    // MARK: - UITableView Methods

    func numberOfSections(in tableView: UITableView) -> Int {
        tableSections().count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        tableRows()[section].count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = tableRows()[indexPath.section][indexPath.row]

        let cell = tableView.dequeueReusableCell(withIdentifier: switchCellId, for: indexPath) as! SwitchCell
        cell.cellSwitch.removeTarget(self, action: nil, for: UIControl.Event.valueChanged)

        switch row {
        case .autoDownload:
            cell.cellLabel?.text = L10n.settingsFilesAutoDownload
            cell.cellSwitch.isOn = ServerSettings.userEpisodeAutoDownload()
            cell.cellSwitch.addTarget(self, action: #selector(autoDownloadToggled(_:)), for: .valueChanged)
            cell.setImage(imageName: "episode-download")
        case .autoUpload:
            cell.cellLabel?.text = L10n.settingsFilesAutoUpload
            cell.setImage(imageName: "plus_upload")
            cell.cellSwitch.isOn = Settings.userFilesAutoUpload()
            cell.cellSwitch.addTarget(self, action: #selector(autoUploadToggled(_:)), for: .valueChanged)
        case .autoAddToUpNext:
            cell.cellLabel?.text = L10n.settingsAutoAdd
            cell.setImage(imageName: "settings_upnext")
            cell.cellSwitch.isOn = Settings.userEpisodeAutoAddToUpNext()
            cell.cellSwitch.addTarget(self, action: #selector(autoAddToUpNextToggled(_:)), for: .valueChanged)
        case .removeFileAfterPlaying:
            cell.cellLabel?.text = L10n.settingsFilesDeleteLocalFile
            cell.setImage(imageName: "delete")
            cell.cellSwitch.isOn = Settings.userEpisodeRemoveFileAfterPlaying()
            cell.cellSwitch.addTarget(self, action: #selector(removeFileAfterPlayingToggled(_:)), for: .valueChanged)
        case .removeFromCloudAfterPlaying:
            cell.cellLabel?.text = L10n.settingsFilesDeleteCloudFile
            cell.setImage(imageName: "settings_cloud_strikethrough")
            cell.cellSwitch.isOn = Settings.userEpisodeRemoveFromCloudAfterPlaying()
            cell.cellSwitch.addTarget(self, action: #selector(removeFromCloudAfterPlayingToggled(_:)), for: .valueChanged)
        case .onlyOnWifi:
            cell.cellLabel?.text = L10n.onlyOnWifi
            cell.setNoImage()
            cell.cellSwitch.isOn = ServerSettings.userEpisodeOnlyOnWifi()
            cell.cellSwitch.addTarget(self, action: #selector(onlyOnWifiToggled(_:)), for: .valueChanged)
            cell.setImage(imageName: "settings_wifi")
        }
        return cell
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        let section = tableSections()[section]
        switch section {
        case .autoSync:
            let syncFooter = (Settings.userFilesAutoUpload() ? L10n.settingsFilesAutoUploadSubtitleOn : L10n.settingsFilesAutoUploadSubtitleOff)
                + "\n"
                + (ServerSettings.userEpisodeAutoDownload() ? L10n.settingsFilesAutoDownloadSubtitleOn : L10n.settingsFilesAutoDownloadSubtitleOff)

            return syncFooter
        case .autoAddToUpNext:
            return L10n.settingsFilesAddUpNextSubtitle
        default:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        ThemeableTable.setHeaderFooterTextColor(on: view)
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return nil
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerFrame = CGRect(x: 0, y: 0, width: 0, height: Constants.Values.tableSectionHeaderHeight)
        let title: String
        let section = tableSections()[section]
        switch section {
        case .autoSync:
            title = L10n.plusFeatures
        case .afterPlaying:
            title = L10n.afterPlaying.localizedUppercase
        default:
            title = ""
        }

        let headerView = SettingsTableHeader(frame: headerFrame, title: title, showLockedImage: false)

        return headerView
    }

    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        return indexPath
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    }

    // MARK: - Switch Actions

    @objc private func autoDownloadToggled(_ sender: UISwitch) {
        ServerSettings.setUserEpisodeAutoDownload(sender.isOn)
        settingsTable.reloadData()
        Settings.trackValueToggled(.settingsFilesAutoDownloadFromCloudToggled, enabled: sender.isOn)
    }

    @objc private func autoUploadToggled(_ sender: UISwitch) {
        Settings.setUserEpisodeAutoUpload(sender.isOn)
        settingsTable.reloadData()
    }

    @objc private func autoAddToUpNextToggled(_ sender: UISwitch) {
        Settings.setUserEpisodeAutoAddToUpNext(sender.isOn)
    }

    @objc private func removeFileAfterPlayingToggled(_ sender: UISwitch) {
        Settings.setUserEpisodeRemoveFileAfterPlaying(sender.isOn)
    }

    @objc private func removeFromCloudAfterPlayingToggled(_ sender: UISwitch) {
        Settings.setUserEpisodeRemoveFromCloudAfterPlayingKey(sender.isOn)
    }

    @objc private func onlyOnWifiToggled(_ sender: UISwitch) {
        ServerSettings.setUserEpisodeOnlyOnWifi(sender.isOn)
        Settings.trackValueToggled(.settingsFilesOnlyOnWifiToggled, enabled: sender.isOn)
    }
}
