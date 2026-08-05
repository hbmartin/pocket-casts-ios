import PocketCastsReadAloud
import SwiftUI

/// Choose a voice, scoped to the document's language by default.
///
/// A device carries on the order of 180 voices across ~50 languages, so the flat
/// list lives one level down behind "All Languages" and this screen shows only
/// what could plausibly read *this* document.
struct VoicePickerView: View {
    @EnvironmentObject private var theme: Theme
    let catalog: VoiceCatalog
    let documentLanguage: String?
    @Binding var selection: SynthesisVoice?
    @ObservedObject var previewPlayer: VoicePreviewPlayer

    private var matchingVoices: [SynthesisVoice] {
        catalog.voices(matching: documentLanguage)
    }

    var body: some View {
        List {
            if !matchingVoices.isEmpty {
                Section(header: header(L10n.readAloudVoicesForDocument)) {
                    ForEach(matchingVoices) { voice in
                        row(voice)
                    }
                }
                .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))
            }

            Section {
                NavigationLink(L10n.readAloudAllLanguages) {
                    AllVoicesView(catalog: catalog, selection: $selection, previewPlayer: previewPlayer)
                        .environmentObject(theme)
                }
                .font(style: .body)
                .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
            }
            .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))

            VoiceQualityExplainerSection()
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.color(for: .primaryUi04, theme: theme).ignoresSafeArea())
        .navigationTitle(L10n.readAloudVoice)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(style: .footnote, weight: .semibold)
            .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
    }

    private func row(_ voice: SynthesisVoice) -> some View {
        VoiceRow(voice: voice, isSelected: selection?.id == voice.id, previewPlayer: previewPlayer) {
            selection = voice
            Analytics.track(.readAloudVoiceChanged, properties: ["voice_quality": voice.quality.analyticsValue])
        }
    }
}

/// Every installed voice, grouped by language.
struct AllVoicesView: View {
    @EnvironmentObject private var theme: Theme
    let catalog: VoiceCatalog
    @Binding var selection: SynthesisVoice?
    @ObservedObject var previewPlayer: VoicePreviewPlayer

    var body: some View {
        List {
            ForEach(catalog.allGroups()) { group in
                Section(header: Text(group.displayName)
                    .font(style: .footnote, weight: .semibold)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                ) {
                    ForEach(group.voices) { voice in
                        VoiceRow(voice: voice, isSelected: selection?.id == voice.id, previewPlayer: previewPlayer) {
                            selection = voice
                            Analytics.track(.readAloudVoiceChanged, properties: ["voice_quality": voice.quality.analyticsValue])
                        }
                    }
                }
                .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.color(for: .primaryUi04, theme: theme).ignoresSafeArea())
        .navigationTitle(L10n.readAloudAllVoicesTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One voice: name, quality badge, a preview button, and a checkmark when
/// selected.
struct VoiceRow: View {
    @EnvironmentObject private var theme: Theme
    let voice: SynthesisVoice
    let isSelected: Bool
    @ObservedObject var previewPlayer: VoicePreviewPlayer
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack {
                    VoiceLabel(voice: voice)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if VoicePreviewPlayer.canPreview(voice) {
                Button {
                    previewPlayer.preview(voice, sampleText: L10n.readAloudVoicePreviewSample)
                    Analytics.track(.readAloudVoicePreviewPlayed)
                } label: {
                    Image(systemName: previewPlayer.isPlaying(voice) ? "stop.circle" : "play.circle")
                        .foregroundColor(AppTheme.color(for: .primaryIcon01, theme: theme))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.readAloudVoicePreviewSample)
            }

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(AppTheme.color(for: .primaryIcon01, theme: theme))
            }
        }
        .font(style: .body)
    }
}
