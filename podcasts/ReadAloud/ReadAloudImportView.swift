import PocketCastsReadAloud
import SwiftUI

/// The sheet between picking a text file and narrating it: confirm the title,
/// see how long it will be, choose a voice.
struct ReadAloudImportView: View {
    @EnvironmentObject private var theme: Theme
    @StateObject var model: ReadAloudImportViewModel
    @StateObject private var previewPlayer = VoicePreviewPlayer()

    let onFinished: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if let error = model.loadError {
                    errorSection(error)
                } else {
                    documentSection
                    voiceSection
                    if model.requiresCostConfirmation {
                        costConfirmationSection
                    }
                    VoiceQualityExplainerSection()
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.color(for: .primaryUi04, theme: theme).ignoresSafeArea())
            .navigationTitle(L10n.readAloudImportTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) {
                        previewPlayer.stop()
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.readAloudGenerate) {
                        Task {
                            previewPlayer.stop()
                            if await model.narrate() { onFinished() }
                        }
                    }
                    .disabled(!model.isReady)
                }
            }
        }
        .task {
            Analytics.track(.readAloudImportShown)
            await model.load()
        }
        .onDisappear { previewPlayer.stop() }
    }

    // MARK: - Sections

    private func errorSection(_ error: ReadAloudError) -> some View {
        Section {
            Text(error.userMessage)
                .font(style: .body)
                .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
        }
        .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))
    }

    private var documentSection: some View {
        Section {
            TextField(L10n.readAloudDocumentTitle, text: $model.title)
                .font(style: .body)
                .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))

            HStack {
                Text(L10n.readAloudCharacterCount(model.characterCount.formatted()))
                Spacer()
                Text(L10n.readAloudEstimatedDuration(Self.durationText(model.estimatedDuration)))
            }
            .font(style: .footnote)
            .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        }
        .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))
    }

    /// Deliberately characters and duration, never money.
    ///
    /// We cannot know the user's plan, their remaining quota, or their per
    /// character rate, and a dollar figure we cannot stand behind is worse than
    /// none. What someone can act on is the size of what they are about to
    /// spend, which is exactly what this shows.
    private var costConfirmationSection: some View {
        Section {
            Toggle(isOn: $model.hasConfirmedCost) {
                Text(L10n.readAloudConfirmToggle(
                    model.characterCount.formatted(),
                    Self.durationText(model.estimatedDuration)
                ))
                .font(style: .footnote)
                .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
            }
        } header: {
            Text(L10n.readAloudConfirmHeader)
                .font(style: .footnote, weight: .semibold)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        }
        .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))
    }

    private var voiceSection: some View {
        Section {
            if let selected = model.selectedVoice {
                NavigationLink {
                    VoicePickerView(
                        catalog: model.catalog,
                        documentLanguage: model.detectedLanguage,
                        selection: $model.selectedVoice,
                        previewPlayer: previewPlayer
                    )
                    .environmentObject(theme)
                } label: {
                    HStack {
                        Text(L10n.readAloudVoice)
                            .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                        Spacer()
                        VoiceLabel(voice: selected)
                    }
                    .font(style: .body)
                }
            }
        } footer: {
            if model.fellBackToDeviceLanguage, let language = model.detectedLanguageName {
                Text(L10n.readAloudNoVoiceForLanguage(language))
                    .font(style: .footnote)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            }
        }
        .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))
    }

    /// "14 min" / "1 hr 3 min" — coarse on purpose, matching how rough the
    /// estimate itself is.
    static func durationText(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute] : [.minute]
        formatter.maximumUnitCount = 2
        return formatter.string(from: max(duration, 60)) ?? ""
    }
}

/// Voice name plus its quality badge, used wherever a voice is shown.
struct VoiceLabel: View {
    @EnvironmentObject private var theme: Theme
    let voice: SynthesisVoice

    var body: some View {
        HStack(spacing: 6) {
            Text(voice.name)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            if let badge = voice.quality.badge {
                Text(badge)
                    .font(style: .caption2, weight: .semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.color(for: .primaryUi05, theme: theme))
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                    .clipShape(Capsule())
            }
        }
    }
}

/// Always shown, in both the picker and settings.
///
/// iOS installs only compact voices by default and they sound robotic, so
/// without this most people would judge the whole feature by its worst voice and
/// never learn better ones exist. There is no public API to trigger the download
/// or deep-link to that Settings pane, so naming the path is all we can do.
struct VoiceQualityExplainerSection: View {
    @EnvironmentObject private var theme: Theme

    var body: some View {
        Section {
            Text(L10n.readAloudVoiceQualityExplainer)
                .font(style: .footnote)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        }
        .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))
    }
}
