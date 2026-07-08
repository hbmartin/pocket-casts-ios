import PocketCastsDataModel
import PocketCastsFileSync
import PocketCastsUtils
import SwiftUI

/// Settings → Sync: the file-sync inspector. Shows where the sync folder
/// lives, what's pending, which devices share it, and offers manual sync,
/// folder change, and diagnostics export.
struct FileSyncSettingsView: View {
    @EnvironmentObject var theme: Theme
    @StateObject private var model = FileSyncSettingsViewModel()

    var body: some View {
        List {
            statusSection
            folderSection
            devicesSection
            diagnosticsSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.color(for: .primaryUi04, theme: theme).ignoresSafeArea())
        .task { await model.refresh() }
        .refreshable { await model.refresh() }
        .sheet(isPresented: $model.showingFolderPicker) {
            FolderPickerView { url in
                Task { await model.folderPicked(url) }
            }
        }
    }

    private var statusSection: some View {
        Section {
            row(L10n.fileSyncStatusState,
                value: model.status.isEnabled ? L10n.fileSyncStatusOn : L10n.fileSyncStatusOff)
            if let kind = model.status.folderKind {
                row(L10n.fileSyncStatusFolder,
                    value: kind == .ubiquity ? L10n.fileSyncFolderICloud : L10n.fileSyncFolderPicked)
            }
            row(L10n.fileSyncStatusPendingChanges, value: "\(model.status.pendingOpCount)")
            if let lastScan = model.status.lastScanDate {
                row(L10n.fileSyncStatusLastSync,
                    value: lastScan.formatted(.relative(presentation: .named)))
            }
            if let error = model.status.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(AppTheme.color(for: .support05, theme: theme))
            }
            Button(action: { Task { await model.syncNow() } }) {
                HStack {
                    Text(L10n.fileSyncActionSyncNow)
                        .foregroundColor(AppTheme.color(for: .primaryInteractive01, theme: theme))
                    Spacer()
                    if model.isSyncing {
                        ProgressView()
                    }
                }
            }
            .disabled(model.isSyncing || !model.status.isEnabled)
        }
    }

    private var folderSection: some View {
        Section(footer: Text(L10n.fileSyncFolderExplanation)
            .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))) {
            Button(L10n.fileSyncActionChooseFolder) {
                model.showingFolderPicker = true
            }
            .foregroundColor(AppTheme.color(for: .primaryInteractive01, theme: theme))
        }
    }

    private var devicesSection: some View {
        Section(header: Text(L10n.fileSyncDevicesHeader)
            .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))) {
            if model.status.devices.isEmpty {
                Text(L10n.fileSyncDevicesEmpty)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            }
            ForEach(model.status.devices) { device in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(displayName(for: device))
                            .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                        if device.isThisDevice {
                            Text(L10n.fileSyncDevicesThisDevice)
                                .font(.caption)
                                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                        }
                        if device.isStale {
                            Text(L10n.fileSyncDevicesStale)
                                .font(.caption)
                                .foregroundColor(AppTheme.color(for: .support05, theme: theme))
                        }
                    }
                    if let lastSeen = device.lastSeen {
                        Text(lastSeen.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                    }
                }
                .swipeActions(edge: .trailing) {
                    if !device.isThisDevice {
                        Button(role: .destructive) {
                            Task { await model.forgetDevice(device.deviceID) }
                        } label: {
                            Text(L10n.fileSyncDevicesForget)
                        }
                    }
                }
            }
        }
    }

    /// Peers that never wrote a device name (or predate device.pb) fall back
    /// to model identifier, then raw device ID — data, not localizable copy.
    private func displayName(for device: FileSyncStatus.Device) -> String {
        if !device.name.isEmpty { return device.name }
        return device.model.isEmpty ? device.deviceID : device.model
    }

    private var diagnosticsSection: some View {
        Section {
            Button(L10n.fileSyncActionExportDiagnostics) {
                Task { await model.exportDiagnostics() }
            }
            .foregroundColor(AppTheme.color(for: .primaryInteractive01, theme: theme))
        }
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
            Spacer()
            Text(value)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        }
    }
}

@MainActor
final class FileSyncSettingsViewModel: ObservableObject {
    @Published var status = FileSyncStatus()
    @Published var isSyncing = false
    @Published var showingFolderPicker = false

    func refresh() async {
        status = await FileSyncManager.shared.status()
    }

    func syncNow() async {
        isSyncing = true
        await FileSyncManager.shared.syncNow()
        await refresh()
        isSyncing = false
    }

    func folderPicked(_ url: URL) async {
        do {
            let bookmark = try BookmarkSyncFolder.makeBookmarkData(forPickedFolder: url)
            try await FileSyncManager.shared.enable(pickedFolderBookmark: bookmark)
            await FileSyncManager.shared.syncNow()
        } catch {
            FileLog.shared.addMessage("FileSync: folder pick failed: \(error)")
        }
        await refresh()
    }

    func forgetDevice(_ deviceID: String) async {
        try? await FileSyncManager.shared.forgetDevice(id: deviceID)
        await refresh()
    }

    /// Writes recent journal state + logs to a temp file and shares it.
    func exportDiagnostics() async {
        let entries = DataManager.sharedManager.unflushedFileSyncEntries(limit: 500)
        var lines = ["Pocket Casts File Sync Diagnostics", "Generated: \(Date())", ""]
        lines.append("Pending journal entries: \(entries.count)")
        for entry in entries {
            let entity = entry.entity.map { "\($0)" } ?? "?"
            let op = entry.op.map { "\($0)" } ?? "?"
            lines.append("\(entry.wallClockMs) \(entity) \(op) \(entry.entityUuid ?? "-") \(entry.fields ?? "")")
        }
        lines.append("")
        for device in status.devices {
            lines.append("Device \(device.deviceID) name=\(device.name) model=\(device.model) lastSeen=\(device.lastSeen.map { "\($0)" } ?? "never")")
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("filesync-diagnostics.txt")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)

        let shareSheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        SceneHelper.rootViewController()?.presentedOrSelf.present(shareSheet, animated: true)
    }
}

private extension UIViewController {
    var presentedOrSelf: UIViewController {
        presentedViewController?.presentedOrSelf ?? self
    }
}
