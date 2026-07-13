import PocketCastsTranscription
import PocketCastsUtils
import SwiftUI

/// Settings page for locally generated diarized transcriptions: engine-mode
/// picker (Apple built-in or a remote provider; local models arrive with
/// Phase 2), remote provider selection with per-provider API key entry and
/// validation, and a language override.
struct TranscriptionSettingsView: View {
    @EnvironmentObject private var theme: Theme
    @StateObject private var model = TranscriptionSettingsViewModel()

    /// Example BCP-47 tag shown as the text-field placeholder (kept as `String`,
    /// not a localized key).
    private let languagePlaceholder = "en-US"

    var body: some View {
        List {
            engineSection

            if model.engineMode == .remoteProvider {
                providerSection
                apiKeySection
            }

            languageSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.color(for: .primaryUi04, theme: theme).ignoresSafeArea())
        .onAppear {
            Analytics.track(.transcriptionSettingsShown)
        }
    }

    private var engineSection: some View {
        Section(
            header: Text(L10n.transcriptionEngineMode)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme)),
            footer: Text(L10n.transcriptionEngineComingSoon)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        ) {
            CheckmarkRow(title: L10n.transcriptionEngineApple,
                         isSelected: model.engineMode == .appleBuiltIn,
                         isEnabled: true) {
                model.select(mode: .appleBuiltIn)
            }
            CheckmarkRow(title: L10n.transcriptionEngineLocalModel,
                         isSelected: model.engineMode == .localModel,
                         isEnabled: false) {}
            CheckmarkRow(title: L10n.transcriptionEngineRemote,
                         isSelected: model.engineMode == .remoteProvider,
                         isEnabled: true) {
                model.select(mode: .remoteProvider)
            }
        }
    }

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
