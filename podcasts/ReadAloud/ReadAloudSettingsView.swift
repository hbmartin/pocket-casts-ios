import PocketCastsDataModel
import PocketCastsReadAloud
import SwiftUI

/// Settings for Read Aloud: the voice new documents start with, where to get
/// better ones, how much space documents use, and a way into the library.
struct ReadAloudSettingsView: View {
    @EnvironmentObject private var theme: Theme
    @StateObject private var model = ReadAloudSettingsViewModel()
    @StateObject private var previewPlayer = VoicePreviewPlayer()

    /// Pushes the library. Injected so the hosting controller owns navigation
    /// and the document picker it needs.
    let onLibraryTapped: () -> Void

    var body: some View {
        List {
            defaultVoiceSection
            VoiceQualityExplainerSection()
            storageSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.color(for: .primaryUi04, theme: theme).ignoresSafeArea())
        .task {
            Analytics.track(.readAloudSettingsShown)
            await model.load()
        }
        .onDisappear { previewPlayer.stop() }
    }

    private var defaultVoiceSection: some View {
        Section {
            NavigationLink {
                VoicePickerView(
                    catalog: model.catalog,
                    documentLanguage: Locale.current.identifier,
                    selection: Binding(
                        get: { model.defaultVoice },
                        set: { model.setDefaultVoice($0) }
                    ),
                    previewPlayer: previewPlayer
                )
                .environmentObject(theme)
            } label: {
                HStack {
                    Text(L10n.readAloudSettingsDefaults)
                        .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                    Spacer()
                    if let voice = model.defaultVoice {
                        VoiceLabel(voice: voice)
                    }
                }
                .font(style: .body)
            }
        } footer: {
            Text(L10n.readAloudSettingsDefaultsFooter)
                .font(style: .footnote)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        }
        .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))
    }

    private var storageSection: some View {
        Section {
            Button(action: onLibraryTapped) {
                HStack {
                    Text(L10n.readAloudSettingsLibrary)
                        .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                    Spacer()
                    Text("\(model.documentCount)")
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack {
                Text(L10n.readAloudSettingsStorage)
                    .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                Spacer()
                Text(model.storageDescription)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            }
        }
        .font(style: .body)
        .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))
    }
}

@MainActor
final class ReadAloudSettingsViewModel: ObservableObject {
    @Published private(set) var catalog = VoiceCatalog(voices: [])
    @Published private(set) var defaultVoice: SynthesisVoice?
    @Published private(set) var documentCount = 0
    @Published private(set) var storageDescription = ""

    private let engine: any SpeechSynthesisEngine
    private let storage: ReadAloudStorage

    init(engine: any SpeechSynthesisEngine = AppleSpeechSynthesisEngine(), storage: ReadAloudStorage = .default) {
        self.engine = engine
        self.storage = storage
    }

    func load() async {
        catalog = VoiceCatalog(voices: (try? await engine.availableVoices(apiKey: nil)) ?? [])
        // Falls back to the best installed voice for this device rather than
        // showing nothing: an unset default still has an effective value, and
        // hiding it would make the row look broken.
        defaultVoice = catalog.voice(id: Settings.readAloudDefaultVoiceId())
            ?? catalog.preferredVoice(for: Locale.current.identifier)

        let documents = DataManager.sharedManager.readAloud.allDocuments()
        documentCount = documents.count
        let bytes = documents.reduce(into: Int64(0)) { total, document in
            let url = storage.sourceURL(relativePath: document.sourcePath)
            if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 {
                total += size
            }
        }
        storageDescription = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func setDefaultVoice(_ voice: SynthesisVoice?) {
        defaultVoice = voice
        Settings.setReadAloudDefaultVoiceId(voice?.id)
    }
}
