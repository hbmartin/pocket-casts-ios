import PocketCastsTranscription
import PocketCastsUtils
import SwiftUI

/// Settings page for locally generated diarized transcriptions. Phase 1 offers
/// the engine-mode picker (Apple built-in only) and a language override; model
/// pickers, provider keys and cellular toggles arrive with their phases.
struct TranscriptionSettingsView: View {
    @EnvironmentObject private var theme: Theme
    @StateObject private var model = TranscriptionSettingsViewModel()

    /// Example BCP-47 tag shown as the text-field placeholder (kept as `String`,
    /// not a localized key).
    private let languagePlaceholder = "en-US"

    var body: some View {
        List {
            Section(
                header: Text(L10n.transcriptionEngineMode)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme)),
                footer: Text(L10n.transcriptionEngineComingSoon)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            ) {
                EngineModeRow(title: L10n.transcriptionEngineApple,
                              isSelected: model.engineMode == .appleBuiltIn,
                              isEnabled: true) {
                    model.select(mode: .appleBuiltIn)
                }
                EngineModeRow(title: L10n.transcriptionEngineLocalModel,
                              isSelected: model.engineMode == .localModel,
                              isEnabled: false) {}
                EngineModeRow(title: L10n.transcriptionEngineRemote,
                              isSelected: model.engineMode == .remoteProvider,
                              isEnabled: false) {}
            }

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
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.color(for: .primaryUi04, theme: theme).ignoresSafeArea())
        .onAppear {
            Analytics.track(.transcriptionSettingsShown)
        }
    }
}

private struct EngineModeRow: View {
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
