import PocketCastsTranscription
import PocketCastsUtils
import SwiftUI

/// Settings page for locally generated diarized transcriptions: engine-mode
/// picker (Apple built-in, downloaded WhisperKit model, or a remote provider),
/// local model management (download/delete, disk usage, cellular gate), speaker
/// detection options, remote provider selection with per-provider API key entry
/// and validation, a language override, and generated-transcript storage.
struct TranscriptionSettingsView: View {
    @EnvironmentObject private var theme: Theme
    @StateObject private var model = TranscriptionSettingsViewModel()

    /// Example BCP-47 tag shown as the text-field placeholder (kept as `String`,
    /// not a localized key).
    private let languagePlaceholder = "en-US"

    var body: some View {
        List {
            engineSection

            if model.engineMode == .localModel {
                modelSection
            }

            if model.engineMode == .remoteProvider {
                providerSection
                apiKeySection
            } else {
                // The SpeakerKit diarizer runs for both local pipeline modes;
                // remote providers label speakers server-side.
                diarizationSection
            }

            languageSection
            storageSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.color(for: .primaryUi04, theme: theme).ignoresSafeArea())
        .onAppear {
            Analytics.track(.transcriptionSettingsShown)
            model.refreshStorage()
        }
        .alert(L10n.transcriptionEngineLocalModel,
               isPresented: Binding(get: { model.modelDownloadError != nil },
                                    set: { if !$0 { model.modelDownloadError = nil } })) {
            Button(L10n.ok) { model.modelDownloadError = nil }
        } message: {
            Text(model.modelDownloadError ?? "")
        }
    }

    private var engineSection: some View {
        Section(
            header: Text(L10n.transcriptionEngineMode)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        ) {
            CheckmarkRow(title: L10n.transcriptionEngineApple,
                         isSelected: model.engineMode == .appleBuiltIn,
                         isEnabled: true) {
                model.select(mode: .appleBuiltIn)
            }
            CheckmarkRow(title: L10n.transcriptionEngineLocalModel,
                         isSelected: model.engineMode == .localModel,
                         isEnabled: true) {
                model.select(mode: .localModel)
            }
            CheckmarkRow(title: L10n.transcriptionEngineRemote,
                         isSelected: model.engineMode == .remoteProvider,
                         isEnabled: true) {
                model.select(mode: .remoteProvider)
            }
        }
    }

    // MARK: - Local model management

    private var modelSection: some View {
        Section(
            header: Text(L10n.transcriptionModelPickerHeader)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme)),
            footer: Text(L10n.transcriptionAllowCellularFooter)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        ) {
            ForEach(model.modelVariants) { variant in
                modelRow(variant)
            }

            modelActionRow

            HStack {
                Text(L10n.transcriptionModelDiskUsage)
                    .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                Spacer()
                Text(Self.formatBytes(model.modelsDiskUsage))
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            }

            Toggle(isOn: Binding(get: { model.allowCellularModelDownloads },
                                 set: { model.setAllowCellularModelDownloads($0) })) {
                Text(L10n.transcriptionAllowCellularDownloads)
                    .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
            }
            .tint(AppTheme.color(for: .primaryInteractive01, theme: theme))
        }
    }

    private func modelRow(_ variant: WhisperKitModelStore.Variant) -> some View {
        let isDownloading = model.modelDownload != .idle
        return Button {
            model.select(modelVariant: variant.id)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(variant.displayName)
                        .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                    Text(subtitle(for: variant))
                        .font(.footnote)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                }
                Spacer()
                if model.selectedModelVariant == variant.id {
                    Image(systemName: "checkmark")
                        .foregroundColor(AppTheme.color(for: .primaryInteractive01, theme: theme))
                }
            }
        }
        .disabled(isDownloading)
    }

    private func subtitle(for variant: WhisperKitModelStore.Variant) -> String {
        let size = Self.formatBytes(Int64(variant.approximateSizeMB) * 1_000_000)
        if model.downloadedModelIds.contains(variant.id) {
            return "\(size) · \(L10n.transcriptionModelDownloaded)"
        }
        return size
    }

    @ViewBuilder private var modelActionRow: some View {
        switch model.modelDownload {
        case .downloading(let fraction):
            HStack(spacing: 12) {
                ProgressView(value: min(max(fraction, 0), 1))
                    .tint(AppTheme.color(for: .primaryInteractive01, theme: theme))
                Text(L10n.transcriptionModelDownloading)
                    .font(.footnote)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                    .layoutPriority(1)
            }
        case .idle:
            if model.isSelectedModelDownloaded {
                Button(L10n.transcriptionModelDelete, role: .destructive) {
                    model.deleteSelectedModel()
                }
                .foregroundColor(AppTheme.color(for: .support05, theme: theme))
            } else {
                let size = Self.formatBytes(Int64((model.selectedVariantInfo?.approximateSizeMB ?? 0)) * 1_000_000)
                Button(L10n.transcriptionModelDownload(size)) {
                    model.downloadSelectedModel()
                }
                .foregroundColor(AppTheme.color(for: .primaryInteractive01, theme: theme))
            }
        }
    }

    // MARK: - Speaker detection

    private var diarizationSection: some View {
        Section(
            header: Text(L10n.transcriptionDiarizationHeader)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme)),
            footer: Text(L10n.transcriptionMaxSpeakersFooter)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        ) {
            Stepper(value: Binding(get: { model.maxSpeakers },
                                   set: { model.setMaxSpeakers($0) }),
                    in: 0...TranscriptionSettingsViewModel.maxSpeakersCap) {
                HStack {
                    Text(L10n.transcriptionMaxSpeakers)
                        .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                    Spacer()
                    Text(model.maxSpeakers == 0 ? L10n.transcriptionMaxSpeakersAuto : "\(model.maxSpeakers)")
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                }
            }
        }
    }

    // MARK: - Remote provider

    private var providerSection: some View {
        Section(
            header: Text(L10n.transcriptionRemoteProvider)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        ) {
            ForEach(model.providers) { provider in
                CheckmarkRow(title: provider.displayName,
                             isSelected: model.selectedProviderId == provider.id,
                             isEnabled: true) {
                    model.select(providerId: provider.id)
                }
            }
        }
    }

    private var apiKeySection: some View {
        Section(
            header: Text(L10n.transcriptionRemoteApiKey)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme)),
            footer: Text(L10n.transcriptionRemoteKeyFooter(model.selectedProvider?.displayName ?? model.selectedProviderId))
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        ) {
            SecureField(L10n.transcriptionRemoteApiKey, text: $model.apiKeyInput)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                .onChange(of: model.apiKeyInput) {
                    model.commitAPIKey()
                }

            HStack {
                Button(L10n.transcriptionValidateKey) {
                    model.validateKey()
                }
                .foregroundColor(AppTheme.color(for: .primaryInteractive01, theme: theme))
                .disabled(model.keyValidation == .validating)

                Spacer()

                validationLabel
            }
        }
    }

    @ViewBuilder private var validationLabel: some View {
        switch model.keyValidation {
        case .idle:
            EmptyView()
        case .validating:
            HStack(spacing: 6) {
                ProgressView()
                Text(L10n.transcriptionKeyValidating)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            }
        case .valid:
            Label(L10n.transcriptionKeyValid, systemImage: "checkmark.circle.fill")
                .foregroundColor(AppTheme.color(for: .support02, theme: theme))
        case .invalid:
            Label(L10n.transcriptionKeyInvalid, systemImage: "xmark.circle.fill")
                .foregroundColor(AppTheme.color(for: .support05, theme: theme))
        case .checkFailed:
            Text(L10n.transcriptionKeyCheckFailed)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        }
    }

    // MARK: - Language

    private var languageSection: some View {
        Section(
            header: Text(L10n.transcriptionLanguageOverride)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme)),
            footer: Text(L10n.transcriptionLanguageOverrideFooter)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        ) {
            TextField(languagePlaceholder, text: $model.languageOverride)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                .onChange(of: model.languageOverride) {
                    model.commitLanguageOverride()
                }
        }
    }

    // MARK: - Generated transcript storage

    private var storageSection: some View {
        Section(
            header: Text(L10n.transcriptionStorageHeader)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        ) {
            HStack {
                Text(L10n.transcriptionStorageUsage)
                    .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                Spacer()
                Text(Self.formatBytes(model.transcriptsDiskUsage))
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            }

            Button(L10n.transcriptionStorageClearAll, role: .destructive) {
                model.showClearAllConfirmation = true
            }
            .foregroundColor(AppTheme.color(for: .support05, theme: theme))
            .disabled(model.transcriptCount == 0)
            .confirmationDialog(L10n.transcriptionStorageClearAll,
                                isPresented: $model.showClearAllConfirmation,
                                titleVisibility: .visible) {
                Button(L10n.transcriptionStorageClearAll, role: .destructive) {
                    model.clearAllTranscriptions()
                }
                Button(L10n.cancel, role: .cancel) {}
            } message: {
                Text(L10n.transcriptionStorageClearAllConfirmation("\(model.transcriptCount)"))
            }
        }
    }

    // MARK: - Formatting

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct CheckmarkRow: View {
    @EnvironmentObject private var theme: Theme

    let title: String
    let isSelected: Bool
    let isEnabled: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack {
                Text(title)
                    .foregroundColor(AppTheme.color(for: isEnabled ? .primaryText01 : .primaryText02, theme: theme))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(AppTheme.color(for: .primaryInteractive01, theme: theme))
                }
            }
        }
        .disabled(!isEnabled)
    }
}
