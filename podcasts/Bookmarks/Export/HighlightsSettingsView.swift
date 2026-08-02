import PocketCastsServer
import PocketCastsUtils
import SwiftUI

/// Settings → Highlights (Highlights program S5): capture behavior and the
/// Markdown folder auto-export. Later slices add prompt styles (S7) and
/// Readwise (S6) here.
struct HighlightsSettingsView: View {
    @EnvironmentObject var theme: Theme
    @StateObject private var model = HighlightsSettingsViewModel()

    var body: some View {
        List {
            captureSection
            exportSection
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.color(for: .primaryUi04, theme: theme).ignoresSafeArea())
        .sheet(isPresented: $model.showingFolderPicker) {
            FolderPickerView { url in
                model.folderPicked(url)
            }
        }
    }

    @ViewBuilder private var captureSection: some View {
        Section {
            if FeatureFlag.highlightEditor.enabled {
                Toggle(L10n.settingsHighlightsReviewAfterCapture, isOn: $model.reviewAfterCapture)
                    .font(style: .body)
            }
            if FeatureFlag.highlightCapture.enabled {
                Picker(L10n.settingsHighlightConfirmationStyle, selection: $model.confirmationStyle) {
                    ForEach(HighlightConfirmationStyle.allCases, id: \.self) { style in
                        Text(style.displayableTitle).tag(style)
                    }
                }
                .font(style: .body)
            }
        } header: {
            Text(L10n.settingsHighlightsCaptureSection)
                .font(style: .footnote, weight: .semibold)
        } footer: {
            Text(L10n.settingsHighlightConfirmationFooter)
                .font(style: .caption)
        }
        .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))
    }

    @ViewBuilder private var exportSection: some View {
        Section {
            if let folderName = model.exportFolderName {
                HStack {
                    Text(L10n.settingsHighlightsExportFolder)
                        .font(style: .body)
                    Spacer()
                    Text(folderName)
                        .font(style: .body)
                        .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                }

                Button(L10n.settingsHighlightsExportNow) {
                    model.exportNow()
                }
                .font(style: .body)

                Button(L10n.settingsHighlightsExportDisable, role: .destructive) {
                    model.disableExport()
                }
                .font(style: .body)
            } else {
                Button(L10n.settingsHighlightsExportChooseFolder) {
                    model.showingFolderPicker = true
                }
                .font(style: .body)
            }
        } header: {
            Text(L10n.settingsHighlightsExportSection)
                .font(style: .footnote, weight: .semibold)
        } footer: {
            Text(L10n.settingsHighlightsExportFooter)
                .font(style: .caption)
        }
        .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))
    }
}

@MainActor
final class HighlightsSettingsViewModel: ObservableObject {
    @Published var showingFolderPicker = false
    @Published private(set) var exportFolderName: String?

    @Published var reviewAfterCapture: Bool {
        didSet { SettingsStore.appSettings.reviewHighlightAfterCapture = reviewAfterCapture }
    }

    @Published var confirmationStyle: HighlightConfirmationStyle {
        didSet { Settings.highlightConfirmationStyle = confirmationStyle }
    }

    private let exporter: HighlightFolderExporter

    init(exporter: HighlightFolderExporter = .shared) {
        self.exporter = exporter
        self.reviewAfterCapture = SettingsStore.appSettings.reviewHighlightAfterCapture
        self.confirmationStyle = Settings.highlightConfirmationStyle
        self.exportFolderName = exporter.isEnabled ? exporter.folderDisplayName : nil
    }

    func folderPicked(_ url: URL) {
        showingFolderPicker = false
        do {
            try exporter.enable(pickedFolder: url)
            exportFolderName = exporter.folderDisplayName
        } catch {
            FileLog.shared.addMessage("[HighlightExport] folder pick failed: \(error)")
        }
    }

    func exportNow() {
        exporter.exportAll()
    }

    func disableExport() {
        exporter.disable()
        exportFolderName = nil
    }
}
