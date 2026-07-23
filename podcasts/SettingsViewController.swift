import PocketCastsServer
import PocketCastsUtils
import SwiftUI
import UIKit

class SettingsViewController: PCViewController, UITableViewDataSource, UITableViewDelegate {
    enum TableRow: String {
        case general, notifications, appearance, storageAndDataUse
        case autoArchive, autoDownload, autoAddToUpNext
        case advancedAudio, devices
        case customFiles, importSteps, opml, backupRestore
        case fileSync
        case transcription
        case about, privacy
        case upNextHistory, foldersHistory
        case headphoneControls
        case developer, beta

        /// Whether the section should be displayed or not
        var visible: Bool {
            switch self {
            case .transcription:
                FeatureFlag.diarizedTranscription.enabled
            default:
                true
            }
        }

        var display: (text: String, image: UIImage?) {
            switch self {
            case .general:
                return (L10n.settingsGeneral, UIImage(named: "profile-settings"))
            case .notifications:
                return (L10n.settingsNotifications, UIImage(named: "settings_notifications"))
            case .appearance:
                return (L10n.settingsAppearance, UIImage(named: "settings_appearance"))
            case .storageAndDataUse:
                return (L10n.settingsStorage, UIImage(named: "settings_storage"))
            case .autoArchive:
                return (L10n.settingsAutoArchive, UIImage(named: "settings_archive"))
            case .autoAddToUpNext:
                return (L10n.settingsAutoAdd, UIImage(named: "playlast"))
            case .autoDownload:
                return (L10n.settingsAutoDownload, UIImage(named: "settings_autodownload"))
            case .importSteps:
                return (L10n.welcomeImportButton, UIImage(named: "settings_import_podcasts"))
            case .opml:
                return (L10n.exportPodcastsOption, UIImage(named: "settings_export_podcasts"))
            case .backupRestore:
                return (L10n.settingsBackupRestore, UIImage(named: "settings_storage"))
            case .about:
                return (L10n.settingsAbout, UIImage(named: "settings_about"))
            case .customFiles:
                return (L10n.files, UIImage(named: "profile_files"))
            case .privacy:
                return (L10n.settingsPrivacy, UIImage(named: "privacy"))
            case .developer:
                return ("Developer", UIImage(systemName: "ladybug.fill"))
            case .beta:
                return ("Beta Features", UIImage(systemName: "testtube.2"))
            case .headphoneControls:
                return (L10n.settingsHeadphoneControls, .init(named: "settings_headphone_controls"))
            case .upNextHistory:
                return (L10n.upNextHistory, .init(named: "upnext"))
            case .foldersHistory:
                return (L10n.foldersHistory, .init(named: "folder-empty"))
            case .fileSync:
                return (L10n.settingsFileSync, UIImage(named: "settings_import_podcasts"))
            case .advancedAudio:
                return (L10n.settingsAdvancedAudio, UIImage(systemName: "slider.horizontal.3"))
            case .devices:
                return (L10n.settingsDevices, UIImage(systemName: "airplayaudio"))
            case .transcription:
                return (L10n.transcriptionSettingsTitle, UIImage(named: "transcript"))
            }
        }
    }

    private var tableData: [[TableRow]] = []

    /// All the possible settings sections
    private let allSections: [[TableRow]] = {
        // nosemgrep: pocketcasts.developer-settings-must-be-debug-only - TestFlight builds intentionally keep the Developer and Beta Features menus (BetaMenu ships localized strings for beta testers; MainTabBarController grants shake-to-feedback to all non-App-Store builds)
        let developerSection: [TableRow] = BuildEnvironment.current != .appStore ? [.developer, .beta] : []

        return [
            developerSection,
            [.general, .notifications, .appearance],
            [.autoArchive, .autoDownload, .autoAddToUpNext],
            [.fileSync],
            [.storageAndDataUse, .headphoneControls, .devices, .advancedAudio, .transcription, .customFiles],
            [.importSteps, .opml, .backupRestore],
            [.upNextHistory, .foldersHistory],
            [.privacy, .about]
        ]
    }()

    private let settingsCellId = "SettingsCell"

    @IBOutlet var settingsTable: UITableView! {
        didSet {
            settingsTable.register(UINib(nibName: "TopLevelSettingsCell", bundle: nil), forCellReuseIdentifier: settingsCellId)
            settingsTable.rowHeight = UITableView.automaticDimension
            settingsTable.estimatedRowHeight = UITableView.automaticDimension
            settingsTable.sectionHeaderHeight = UITableView.automaticDimension
            settingsTable.estimatedSectionHeaderHeight = Constants.Values.tableSectionHeaderHeight
            settingsTable.sectionFooterHeight = UITableView.automaticDimension
            settingsTable.estimatedSectionFooterHeight = Constants.Values.tableSectionHeaderHeight
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.settings
        insetAdjuster.setupInsetAdjustmentsForMiniPlayer(scrollView: settingsTable)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        reloadTable()
    }

    // MARK: - UITableView Methods

    func numberOfSections(in tableView: UITableView) -> Int {
        tableData.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        tableData[section].count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: settingsCellId, for: indexPath) as! TopLevelSettingsCell
        cell.plusIndicator.isHidden = true

        let tableRow = tableData[indexPath.section][indexPath.row]
        cell.settingsLabel.text = tableRow.display.text
        cell.settingsLabel.accessibilityIdentifier = tableRow.rawValue
        cell.settingsImage.image = tableRow.display.image

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let tableRow = tableData[indexPath.section][indexPath.row]
        selectRow(tableRow)
    }

    func selectRow(_ tableRow: TableRow) {
        switch tableRow {
        case .general:
            navigationController?.pushViewController(GeneralSettingsViewController(), animated: true)
        case .notifications:
            navigationController?.pushViewController(NotificationsViewController(), animated: true)
        case .appearance:
            navigationController?.pushViewController(AppearanceViewController(), animated: true)
        case .storageAndDataUse:
            navigationController?.pushViewController(StorageAndDataUseViewController(), animated: true)
        case .autoAddToUpNext:
            navigationController?.pushViewController(AutoAddToUpNextViewController(), animated: true)
        case .autoArchive:
            navigationController?.pushViewController(AutoArchiveViewController(), animated: true)
        case .autoDownload:
            navigationController?.pushViewController(DownloadSettingsViewController(), animated: true)
        case .importSteps:
            let controller = ImportViewModel.make(source: "settings", showSubtitle: false)
            navigationController?.present(controller, animated: true)
        case .opml:
            navigationController?.pushViewController(ImportExportViewController(), animated: true)
        case .backupRestore:
            let controller = BackupRestoreViewController()
            controller.title = L10n.settingsBackupRestore
            navigationController?.pushViewController(controller, animated: true)
        case .about:
            Analytics.track(.settingsAboutShown)

            let aboutView = AboutView(dismissAction: { [weak self] in
                self?.navigationController?.dismiss(animated: true, completion: nil)
            }).environmentObject(Theme.sharedTheme)
            let hostingController = PCHostingController(rootView: aboutView)

            navigationController?.present(hostingController, animated: true, completion: nil)
        case .customFiles:
            navigationController?.pushViewController(UploadedSettingsViewController(), animated: true)
        case .privacy:
            navigationController?.pushViewController(PrivacySettingsViewController(), animated: true)
        case .developer:
            let hostingController = UIHostingController(rootView: DeveloperMenu().setupDefaultEnvironment())
            navigationController?.pushViewController(hostingController, animated: true)
        case .beta:
            let hostingController = UIHostingController(rootView: BetaMenu().setupDefaultEnvironment())
            hostingController.title = "Beta Features"
            navigationController?.pushViewController(hostingController, animated: true)
        case .headphoneControls:
            navigationController?.pushViewController(HeadphoneSettingsViewController(), animated: true)
        case .upNextHistory:
            let upNextHistory = UpNextHistoryViewController()
            navigationController?.pushViewController(upNextHistory, animated: true)
        case .foldersHistory:
            let foldersHistoryViewController = FolderHistoryViewController()
            navigationController?.pushViewController(foldersHistoryViewController, animated: true)
        case .fileSync:
            let syncView = FileSyncSettingsView().environmentObject(Theme.sharedTheme)
            let hostingController = PCHostingController(rootView: syncView)
            hostingController.title = L10n.settingsFileSync
            navigationController?.pushViewController(hostingController, animated: true)
        case .advancedAudio:
            let tuningView = AdvancedAudioSettingsView().environmentObject(Theme.sharedTheme)
            let hostingController = PCHostingController(rootView: tuningView)
            hostingController.title = L10n.settingsAdvancedAudio
            navigationController?.pushViewController(hostingController, animated: true)
        case .devices:
            let devicesView = DevicesSettingsView().environmentObject(Theme.sharedTheme)
            let hostingController = PCHostingController(rootView: devicesView)
            hostingController.title = L10n.settingsDevices
            navigationController?.pushViewController(hostingController, animated: true)
        case .transcription:
            let transcriptionView = TranscriptionSettingsView().environmentObject(Theme.sharedTheme)
            let hostingController = PCHostingController(rootView: transcriptionView)
            hostingController.title = L10n.transcriptionSettingsTitle
            navigationController?.pushViewController(hostingController, animated: true)
        }
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        1
    }

    private func reloadTable() {
        tableData = allSections.compactMap {
            $0.filter(\.visible).nilIfEmpty()
        }

        settingsTable.reloadData()
    }
}
