import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils
import SwiftUI
import UniformTypeIdentifiers

class BackupRestoreViewController: ThemedHostingController<BackupRestoreView> {
    convenience init() {
        self.init(rootView: BackupRestoreView())
    }
}

/// User-facing library backup and restore. A backup is a plain folder — the SQLite
/// database (episodes included) plus the app-settings JSON — exported to a user-chosen
/// location via the document picker. No Pocket Casts account or servers involved.
struct BackupRestoreView: View {
    @EnvironmentObject var theme: Theme

    @State private var exportFolder: ExportFolder?
    @State private var showingRestoreConfirm = false
    @State private var showingRestorePicker = false
    @State private var resultAlert: ResultAlert?

    private struct ExportFolder: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    private struct ResultAlert: Identifiable {
        let title: String
        let message: String
        var id: String { title }
    }

    var body: some View {
        List {
            Section {
                Button(L10n.settingsBackupNow) {
                    backUp()
                }
                .listRowBackground(theme.primaryUi02)
            } footer: {
                Text(L10n.settingsBackupFooter)
                    .foregroundStyle(theme.primaryText02)
            }

            Section {
                Button(L10n.settingsRestore, role: .destructive) {
                    showingRestoreConfirm = true
                }
                .listRowBackground(theme.primaryUi02)
            } footer: {
                Text(L10n.settingsRestoreFooter)
                    .foregroundStyle(theme.primaryText02)
            }
        }
        .modifier(HiddenScrollContentBackground())
        .background(theme.primaryUi04)
        .navigationTitle(L10n.settingsBackupRestore)
        .sheet(item: $exportFolder) { folder in
            BackupFolderExporter(folderURL: folder.url)
        }
        .alert(L10n.settingsRestoreConfirmTitle, isPresented: $showingRestoreConfirm) {
            Button(L10n.settingsRestore, role: .destructive) { showingRestorePicker = true }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.settingsRestoreConfirmMessage)
        }
        .fileImporter(isPresented: $showingRestorePicker, allowedContentTypes: [.folder]) { result in
            if case let .success(folderURL) = result {
                restore(from: folderURL)
            }
        }
        .alert(item: $resultAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text(L10n.ok)))
        }
        .applyDefaultThemeOptions()
    }

    // MARK: - Backup

    private func backUp() {
        do {
            let folderURL = try BackupRestoreView.stageBackupFolder()
            exportFolder = ExportFolder(url: folderURL)
        } catch {
            FileLog.shared.addMessage("BackupRestore: backup failed: \(error)")
            resultAlert = ResultAlert(title: L10n.settingsBackupFailed, message: error.localizedDescription)
        }
    }

    static func stageBackupFolder() throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        let folderName = "Pocket Casts Backup \(formatter.string(from: Date()))"

        let folderURL = FileManager.default.temporaryDirectory.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.removeItem(at: folderURL)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        try DataManager.sharedManager.backupDatabase(to: folderURL.appendingPathComponent(BackupFile.database).path)
        if let settingsData = SettingsStore.appSettings.exportSettingsJSON() {
            try settingsData.write(to: folderURL.appendingPathComponent(BackupFile.settings))
        }

        return folderURL
    }

    // MARK: - Restore

    private func restore(from folderURL: URL) {
        let accessing = folderURL.startAccessingSecurityScopedResource()
        defer { if accessing { folderURL.stopAccessingSecurityScopedResource() } }

        let databaseURL = folderURL.appendingPathComponent(BackupFile.database)
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            resultAlert = ResultAlert(title: L10n.settingsRestoreFailed, message: L10n.settingsRestoreInvalidBackup)
            return
        }

        do {
            let stagingPath = DataManager.pathToDbBackup()
            try? FileManager.default.removeItem(atPath: stagingPath)
            try FileManager.default.copyItem(at: databaseURL, to: URL(fileURLWithPath: stagingPath))
        } catch {
            FileLog.shared.addMessage("BackupRestore: staging backup failed: \(error)")
            resultAlert = ResultAlert(title: L10n.settingsRestoreFailed, message: error.localizedDescription)
            return
        }

        let restored = DataManager.sharedManager.restoreAllData()
        try? FileManager.default.removeItem(atPath: DataManager.pathToDbBackup())

        guard restored else {
            resultAlert = ResultAlert(title: L10n.settingsRestoreFailed, message: L10n.settingsRestoreInvalidBackup)
            return
        }

        if let settingsData = try? Data(contentsOf: folderURL.appendingPathComponent(BackupFile.settings)) {
            SettingsStore.appSettings.importSettingsJSON(settingsData)
        }

        NotificationCenter.postOnMainThread(notification: ServerNotifications.podcastsRefreshed, object: nil)
        FileLog.shared.addMessage("BackupRestore: restore completed")
        resultAlert = ResultAlert(title: L10n.settingsRestoreDoneTitle, message: L10n.settingsRestoreDoneMessage)
    }

    private enum BackupFile {
        static let database = "library.sqlite3"
        static let settings = "settings.json"
    }
}

/// Wraps `UIDocumentPickerViewController(forExporting:)` so the staged backup folder can
/// be moved wherever the user chooses (Files, iCloud Drive, a USB drive…).
private struct BackupFolderExporter: UIViewControllerRepresentable {
    let folderURL: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [folderURL], asCopy: true)
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}

#Preview {
    BackupRestoreView()
        .environmentObject(Theme.sharedTheme)
}
