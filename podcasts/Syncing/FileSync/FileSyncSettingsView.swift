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
}
