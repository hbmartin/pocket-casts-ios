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
            if FeatureFlag.readwiseSync.enabled {
                readwiseSection
            }
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
                Toggle(L10n.settingsHighlightsResurfacing, isOn: $model.resurfacingEnabled)
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
            if FeatureFlag.highlightPromptStyles.enabled {
                Picker(L10n.settingsHighlightsPromptStyle, selection: $model.promptStyle) {
                    ForEach(HighlightPromptStyle.allCases, id: \.self) { style in
                        Text(style.displayableTitle).tag(style)
                    }
                }
                .font(style: .body)

                TextField(L10n.settingsHighlightsPromptCustomPlaceholder, text: $model.promptCustomText, axis: .vertical)
                    .font(style: .body)
                    .lineLimit(1...3)
                    .onChange(of: model.promptCustomText) { _, newValue in
                        if newValue.count > PromptStyleLibrary.customStyleCharacterCap {
                            model.promptCustomText = String(newValue.prefix(PromptStyleLibrary.customStyleCharacterCap))
                        }
                    }
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

    @ViewBuilder private var readwiseSection: some View {
        Section {
            if model.readwiseConnected {
                HStack {
                    Text(L10n.settingsHighlightsReadwiseConnected)
                        .font(style: .body)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.color(for: .support02, theme: theme))
                }
                Button(L10n.settingsHighlightsReadwiseDisconnect, role: .destructive) {
                    Task { await model.disconnectReadwise() }
                }
                .font(style: .body)
            } else {
                SecureField(L10n.settingsHighlightsReadwiseTokenPlaceholder, text: $model.readwiseTokenInput)
                    .font(style: .body)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button(model.readwiseValidating ? L10n.settingsHighlightsReadwiseValidating : L10n.settingsHighlightsReadwiseConnect) {
                    Task { await model.connectReadwise() }
                }
                .font(style: .body)
                .disabled(model.readwiseValidating || model.readwiseTokenInput.trim().isEmpty)
                if model.readwiseValidationFailed {
                    Text(L10n.settingsHighlightsReadwiseInvalidToken)
                        .font(style: .caption)
                        .foregroundStyle(AppTheme.color(for: .support05, theme: theme))
                }
            }
        } header: {
            Text(L10n.settingsHighlightsReadwiseSection)
                .font(style: .footnote, weight: .semibold)
        } footer: {
            Text(L10n.settingsHighlightsReadwiseFooter)
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

    /// The weekly "from your highlights" notification (opt-in, device-local).
    @Published var resurfacingEnabled: Bool {
        didSet {
            NotificationsGroup.fromYourHighlights.setEnabled(resurfacingEnabled)
            if resurfacingEnabled {
                NotificationsCoordinator.shared.setupNotifications(for: .fromYourHighlights)
            } else {
                NotificationsCoordinator.shared.disableNotifications(for: .fromYourHighlights)
            }
        }
    }

    @Published var confirmationStyle: HighlightConfirmationStyle {
        didSet { Settings.highlightConfirmationStyle = confirmationStyle }
    }

    @Published var promptStyle: HighlightPromptStyle {
        didSet { SettingsStore.appSettings.highlightStylePreset = promptStyle.rawValue }
    }

    @Published var promptCustomText: String {
        didSet { SettingsStore.appSettings.highlightStyleCustom = promptCustomText }
    }

    @Published var readwiseTokenInput = ""
    @Published private(set) var readwiseConnected: Bool
    @Published private(set) var readwiseValidating = false
    @Published private(set) var readwiseValidationFailed = false

    private let exporter: HighlightFolderExporter
    private let readwise: ReadwiseSyncManager

    init(exporter: HighlightFolderExporter = .shared, readwise: ReadwiseSyncManager = .shared) {
        self.exporter = exporter
        self.readwise = readwise
        self.reviewAfterCapture = SettingsStore.appSettings.reviewHighlightAfterCapture
        self.resurfacingEnabled = Settings.notificationsFromYourHighlights
        self.confirmationStyle = Settings.highlightConfirmationStyle
        self.promptStyle = HighlightPromptStyle(rawValue: SettingsStore.appSettings.highlightStylePreset) ?? .standard
        self.promptCustomText = SettingsStore.appSettings.highlightStyleCustom
        self.exportFolderName = exporter.isEnabled ? exporter.folderDisplayName : nil
        self.readwiseConnected = readwise.isEnabled
    }

    func connectReadwise() async {
        readwiseValidating = true
        readwiseValidationFailed = false
        let accepted = await readwise.updateToken(readwiseTokenInput)
        readwiseValidating = false
        if accepted {
            readwiseConnected = true
            readwiseTokenInput = ""
        } else {
            readwiseValidationFailed = true
        }
    }

    func disconnectReadwise() async {
        _ = await readwise.updateToken(nil)
        readwiseConnected = false
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
