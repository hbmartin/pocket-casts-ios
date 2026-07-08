import PocketCastsDataModel
import PocketCastsFileSync
import PocketCastsUtils
import SwiftUI
import UIKit

struct FileSyncSettingsView: View {
    @EnvironmentObject private var theme: Theme
    @StateObject private var model = FileSyncSettingsViewModel()

    var body: some View {
        List {
            FileSyncStatusSection(
                status: model.status,
                isSyncing: model.isSyncing,
                syncNow: { Task { await model.syncNow() } }
            )
            FileSyncFolderSection(showFolderPicker: {
                model.showingFolderPicker = true
            })
            FileSyncDevicesSection(
                devices: model.status.devices,
                forgetDevice: { deviceID in Task { await model.forgetDevice(deviceID) } }
            )
            FileSyncDiagnosticsSection(exportDiagnostics: {
                Task { await model.exportDiagnostics() }
            })
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
}

private struct FileSyncStatusSection: View {
    @EnvironmentObject private var theme: Theme

    let status: FileSyncStatus
    let isSyncing: Bool
    let syncNow: () -> Void

    var body: some View {
        Section {
            FileSyncValueRow(title: L10n.fileSyncStatusState,
                             value: status.isEnabled ? L10n.fileSyncStatusOn : L10n.fileSyncStatusOff)
            if let kind = status.folderKind {
                FileSyncValueRow(title: L10n.fileSyncStatusFolder,
                                 value: kind == .ubiquity ? L10n.fileSyncFolderIcloud : L10n.fileSyncFolderPicked)
            }
            FileSyncValueRow(title: L10n.fileSyncStatusPendingChanges, value: "\(status.pendingOpCount)")
            if let lastScan = status.lastScanDate {
                FileSyncValueRow(title: L10n.fileSyncStatusLastSync,
                                 value: lastScan.formatted(.relative(presentation: .named)))
            }
            if let error = status.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(AppTheme.color(for: .support05, theme: theme))
            }
            Button(action: syncNow) {
                HStack {
                    Text(L10n.fileSyncActionSyncNow)
                        .foregroundColor(AppTheme.color(for: .primaryInteractive01, theme: theme))
                    Spacer()
                    if isSyncing {
                        ProgressView()
                    }
                }
            }
            .disabled(isSyncing || !status.isEnabled)
        }
    }
}

private struct FileSyncFolderSection: View {
    @EnvironmentObject private var theme: Theme

    let showFolderPicker: () -> Void

    var body: some View {
        Section(footer: Text(L10n.fileSyncFolderExplanation)
            .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))) {
            Button(L10n.fileSyncActionChooseFolder, action: showFolderPicker)
                .foregroundColor(AppTheme.color(for: .primaryInteractive01, theme: theme))
        }
    }
}

private struct FileSyncDevicesSection: View {
    @EnvironmentObject private var theme: Theme

    let devices: [FileSyncStatus.Device]
    let forgetDevice: (String) -> Void

    var body: some View {
        Section(header: Text(L10n.fileSyncDevicesHeader)
            .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))) {
            if devices.isEmpty {
                Text(L10n.fileSyncDevicesEmpty)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            }
            ForEach(devices) { device in
                FileSyncDeviceRow(device: device)
                    .swipeActions(edge: .trailing) {
                        if !device.isThisDevice {
                            Button(role: .destructive) {
                                forgetDevice(device.deviceID)
                            } label: {
                                Text(L10n.fileSyncDevicesForget)
                            }
                        }
                    }
            }
        }
    }
}

private struct FileSyncDeviceRow: View {
    @EnvironmentObject private var theme: Theme

    let device: FileSyncStatus.Device

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(displayName)
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
    }

    private var displayName: String {
        if !device.name.isEmpty { return device.name }
        return device.model.isEmpty ? device.deviceID : device.model
    }
}

private struct FileSyncDiagnosticsSection: View {
    @EnvironmentObject private var theme: Theme

    let exportDiagnostics: () -> Void

    var body: some View {
        Section {
            Button(L10n.fileSyncActionExportDiagnostics, action: exportDiagnostics)
                .foregroundColor(AppTheme.color(for: .primaryInteractive01, theme: theme))
        }
    }
}

private struct FileSyncValueRow: View {
    @EnvironmentObject private var theme: Theme

    let title: String
    let value: String

    var body: some View {
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
