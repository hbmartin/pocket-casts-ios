import PocketCastsUtils
import UIKit

class UploadedSettingsViewController: PCViewController, UITableViewDelegate, UITableViewDataSource {
    private let switchCellId = "SwitchCell"

    private enum TableSections: Int {
        case autoAddToUpNext
        case afterPlaying
    }

    private enum TableRows: Int {
        case autoAddToUpNext
        case removeFileAfterPlaying
    }

    private let rows: [[TableRows]] = [[.autoAddToUpNext], [.removeFileAfterPlaying]]

    @IBOutlet var settingsTable: UITableView! {
        didSet {
            settingsTable.register(
                UINib(nibName: "SwitchCell", bundle: nil),
                forCellReuseIdentifier: switchCellId
            )
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

    func numberOfSections(in tableView: UITableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows[section].count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = rows[indexPath.section][indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: switchCellId, for: indexPath) as! SwitchCell
        cell.cellSwitch.removeTarget(self, action: nil, for: .valueChanged)

        switch row {
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
        }
        return cell
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == TableSections.autoAddToUpNext.rawValue ? L10n.settingsFilesAddUpNextSubtitle : nil
    }

    func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        ThemeableTable.setHeaderFooterTextColor(on: view)
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        nil
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let frame = CGRect(x: 0, y: 0, width: 0, height: Constants.Values.tableSectionHeaderHeight)
        let title = section == TableSections.afterPlaying.rawValue ? L10n.afterPlaying.localizedUppercase : ""
        return SettingsTableHeader(frame: frame, title: title, showLockedImage: false)
    }

    @objc private func autoAddToUpNextToggled(_ sender: UISwitch) {
        Settings.setUserEpisodeAutoAddToUpNext(sender.isOn)
    }

    @objc private func removeFileAfterPlayingToggled(_ sender: UISwitch) {
        Settings.setUserEpisodeRemoveFileAfterPlaying(sender.isOn)
    }
}
