import PocketCastsReadAloud
import SwiftUI

/// Write or paste text to be narrated.
///
/// Deliberately a writing surface only: it collects a title and a body, then
/// hands the extracted result to the same review sheet a picked file goes
/// through. Keeping the two apart means the voice, the duration estimate and —
/// once a paid provider ships — the cost confirmation all live in one place,
/// seen after the text exists and before anything is committed.
struct ReadAloudComposeView: View {
    @EnvironmentObject private var theme: Theme
    @StateObject private var model = ReadAloudComposeViewModel()
    @FocusState private var bodyFocused: Bool

    let onCancel: () -> Void
    /// Hands the extracted text on to the review sheet.
    let onNext: (NarrationImporter.Preview) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(L10n.readAloudDocumentTitle, text: $model.title)
                        .font(style: .body)
                        .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                }
                .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))

                Section {
                    TextEditor(text: $model.text)
                        .font(style: .body)
                        .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 220)
                        .focused($bodyFocused)
                        .overlay(alignment: .topLeading) {
                            // TextEditor has no placeholder of its own.
                            if model.text.isEmpty {
                                Text(L10n.readAloudComposePlaceholder)
                                    .font(style: .body)
                                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } footer: {
                    Text(model.footerText)
                        .font(style: .footnote)
                        .foregroundColor(
                            AppTheme.color(for: model.isOverLimit ? .support05 : .primaryText02, theme: theme)
                        )
                }
                .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.color(for: .primaryUi04, theme: theme).ignoresSafeArea())
            .navigationTitle(L10n.readAloudComposeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.next) {
                        if let preview = model.makePreview() { onNext(preview) }
                    }
                    .disabled(!model.canContinue)
                }
            }
        }
        .onAppear {
            Analytics.track(.readAloudComposeShown)
            bodyFocused = true
        }
    }
}

@MainActor
final class ReadAloudComposeViewModel: ObservableObject {
    @Published var title = ""
    @Published var text = ""

    private let importer: NarrationImporter

    init(importer: NarrationImporter = NarrationImporter()) {
        self.importer = importer
    }

    /// Counts what will actually be narrated, so it matches the number the
    /// review sheet then shows. Whitespace-only input counts as nothing.
    var characterCount: Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : text.count
    }

    var isOverLimit: Bool {
        characterCount > ExtractedDocument.maximumCharacterCount
    }

    var canContinue: Bool {
        characterCount > 0 && !isOverLimit
    }

    var footerText: String {
        isOverLimit
            ? L10n.readAloudErrorTooLarge
            : L10n.readAloudCharacterCount(characterCount.formatted())
    }

    /// Extracts now rather than at commit time so the review sheet has a real
    /// character count and detected language to show, and so a document that
    /// can't be extracted fails here rather than two screens later.
    func makePreview() -> NarrationImporter.Preview? {
        try? importer.preview(text: text, title: title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty())
    }
}

private extension String {
    func nilIfEmpty() -> String? {
        isEmpty ? nil : self
    }
}
