import PocketCastsDataModel
import PocketCastsReadAloud
import SwiftUI

/// The Read Aloud library: your documents, each with the narrations made from
/// it, and the button that imports a new one.
///
/// This is the queue screen too — a rendering narration shows its progress here,
/// and a failed one its retry. Documents and their attempts are the same list
/// because they are the same thing to the person looking at it.
struct ReadAloudLibraryView: View {
    @EnvironmentObject private var theme: Theme
    @StateObject private var model = ReadAloudLibraryViewModel()
    @State private var importSource: ReadAloudImportViewModel.Source?

    /// Presents the document picker. Injected because the picker is UIKit and
    /// the hosting controller owns it.
    let onImportTapped: () -> Void

    var body: some View {
        List {
            Section {
                Button(L10n.readAloudNarrateDocument, action: onImportTapped)
                    .font(style: .body, weight: .medium)
                    .foregroundColor(AppTheme.color(for: .primaryInteractive01, theme: theme))
            }
            .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))

            if model.entries.isEmpty {
                emptyState
            } else {
                ForEach(model.entries) { entry in
                    documentSection(entry)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.color(for: .primaryUi04, theme: theme).ignoresSafeArea())
        .navigationTitle(L10n.readAloudLibraryTitle)
        .onAppear {
            Analytics.track(.readAloudLibraryShown)
            model.start()
        }
        .sheet(item: $importSource) { source in
            ReadAloudImportView(
                model: ReadAloudImportViewModel(source: source),
                onFinished: {
                    importSource = nil
                    model.refresh()
                },
                onCancel: { importSource = nil }
            )
            .environmentObject(theme)
        }
        .alert(
            L10n.readAloudDeleteDocumentConfirmTitle,
            isPresented: Binding(
                get: { model.pendingDeletion != nil },
                set: { if !$0 { model.pendingDeletion = nil } }
            ),
            presenting: model.pendingDeletion
        ) { document in
            Button(L10n.delete, role: .destructive) { model.confirmDelete(document) }
            Button(L10n.cancel, role: .cancel) { model.pendingDeletion = nil }
        } message: { _ in
            Text(L10n.readAloudDeleteDocumentConfirmMessage)
        }
    }

    // MARK: - Sections

    private var emptyState: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.readAloudLibraryEmptyTitle)
                    .font(style: .body, weight: .medium)
                    .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                Text(L10n.readAloudLibraryEmptyMessage)
                    .font(style: .footnote)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))
    }

    private func documentSection(_ entry: ReadAloudLibraryViewModel.Entry) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.document.title)
                    .font(style: .body, weight: .medium)
                    .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                Text(L10n.readAloudCharacterCount(Int(entry.document.characterCount).formatted()))
                    .font(style: .caption)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            }

            ForEach(entry.narrations, id: \.uuid) { narration in
                narrationRow(narration)
            }

            Button(L10n.readAloudNarrateAgain) {
                importSource = .existingDocument(entry.document)
            }
            .font(style: .footnote)
            .foregroundColor(AppTheme.color(for: .primaryInteractive01, theme: theme))

            Button(L10n.readAloudDeleteDocument, role: .destructive) {
                model.pendingDeletion = entry.document
            }
            .font(style: .footnote)
        }
        .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))
    }

    @ViewBuilder
    private func narrationRow(_ narration: NarrationRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(narration.voiceName)
                    .font(style: .subheadline)
                    .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                Spacer()
                Text(statusText(narration))
                    .font(style: .caption)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            }

            if narration.narrationState == .rendering {
                ProgressView(value: narration.progress)
                    .tint(AppTheme.color(for: .primaryInteractive01, theme: theme))
            }

            HStack(spacing: 16) {
                if narration.narrationState == .failed || narration.narrationState == .cancelled {
                    Button(L10n.readAloudRetry) { model.retry(narration) }
                }
                if narration.isActive {
                    Button(L10n.readAloudCancelNarration) { model.cancel(narration) }
                }
                if narration.narrationState == .completed {
                    Button(L10n.readAloudDeleteNarration, role: .destructive) { model.delete(narration) }
                }
            }
            .font(style: .caption)
            .buttonStyle(.plain)
            .foregroundColor(AppTheme.color(for: .primaryInteractive01, theme: theme))
        }
        .padding(.vertical, 2)
    }

    private func statusText(_ narration: NarrationRecord) -> String {
        switch narration.narrationState {
        case .queued:
            L10n.readAloudStatusQueued
        case .rendering:
            L10n.readAloudStatusRendering(narration.progress.formatted(.percent.precision(.fractionLength(0))))
        case .completed:
            ReadAloudImportView.durationText(narration.outputDuration ?? 0)
        case .failed:
            L10n.readAloudStatusFailed
        case .cancelled:
            L10n.readAloudStatusCancelled
        }
    }
}

extension ReadAloudImportViewModel.Source: Identifiable {
    var id: String {
        switch self {
        case .file(let url, _): "file:\(url.absoluteString)"
        case .existingDocument(let document): "document:\(document.uuid)"
        }
    }
}
