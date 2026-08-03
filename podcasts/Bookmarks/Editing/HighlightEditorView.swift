import CoreMedia
import PocketCastsDataModel
import SwiftUI

/// The highlight editor sheet (Highlights program S4): trim the excerpt window
/// against the transcript, edit the title, and manage tags. Reuses the clip
/// trim scrubber (`MediaTrimView`) over a ±2 minute window around the capture
/// anchor, with a looping preview through `ClipPlaybackManager`.
struct HighlightEditorView: View {
    @ObservedObject var model: HighlightEditorViewModel
    @EnvironmentObject var theme: Theme

    /// Bridges the editor's absolute-time selection into the clip player's model.
    @StateObject private var clipTime: ClipTime

    init(model: HighlightEditorViewModel) {
        self.model = model
        _clipTime = StateObject(wrappedValue: ClipTime(start: 0, end: 0))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(L10n.bookmarkDefaultTitle, text: $model.title)
                        .font(style: .body)
                } header: {
                    Text(L10n.changeBookmarkTitle)
                        .font(style: .footnote, weight: .semibold)
                }
                .listRowBackground(AppTheme.color(for: .primaryUi02, theme: theme))

                excerptSection

                tagsSection
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.color(for: .primaryUi01, theme: theme).ignoresSafeArea())
            .navigationTitle(L10n.highlightEditorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { model.cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.fileUploadSave) { model.save() }
                        .fontWeight(.semibold)
                        .disabled(model.isSaving)
                }
            }
            .overlay(alignment: .bottom) {
                if model.saveFailed {
                    Text(L10n.pleaseTryAgainLater)
                        .font(style: .footnote, weight: .medium)
                        .foregroundStyle(AppTheme.color(for: .support05, theme: theme))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(AppTheme.color(for: .primaryUi02, theme: theme), in: Capsule())
                        .padding(.bottom, 12)
                }
            }
        }
        .task { await model.sheetAppeared() }
        .onChange(of: model.selectionStart) { _, newValue in clipTime.start = newValue }
        .onChange(of: model.selectionEnd) { _, newValue in clipTime.end = newValue }
        .onDisappear { ClipPlaybackManager.shared.stop() }
    }

    // MARK: - Excerpt trim

    @ViewBuilder private var excerptSection: some View {
        Section {
            if model.isLoadingTranscript {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .tint(AppTheme.loadingActivityColor().color)
            } else if model.canTrim {
                if let excerpt = model.selectionExcerpt {
                    Text(excerpt)
                        .font(style: .subheadline)
                        .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                        .lineLimit(6)
                }

                trimBar
            } else {
                Text(L10n.highlightEditorNoTranscript)
                    .font(style: .footnote)
                    .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
            }
        } header: {
            Text(L10n.highlightEditorTrimSection)
                .font(style: .footnote, weight: .semibold)
        }
        .listRowBackground(AppTheme.color(for: .primaryUi02, theme: theme))
    }

    @ViewBuilder private var trimBar: some View {
        HStack(spacing: 12) {
            if let episode = model.episode {
                TrimPlayButton(isPlaying: playingBinding(for: episode))
                    .frame(width: 56, height: 40)
            }

            // MediaTrimView spans the pannable window; its bindings are offset
            // from the window origin because the scrubber's timeline starts at 0.
            MediaTrimView(
                duration: model.windowEnd - model.windowStart,
                startTime: offsetBinding($model.selectionStart),
                endTime: offsetBinding($model.selectionEnd),
                playTime: offsetBinding(playheadBinding)
            )
            .frame(height: 72)
        }
    }

    /// The clip player's playhead, surfaced for the scrubber's indicator.
    private var playheadBinding: Binding<TimeInterval> {
        Binding(
            get: {
                guard let playbackTime = ClipPlaybackManager.shared.currentTime else { return model.selectionStart }
                return model.transcriptTime(forPlaybackTime: playbackTime) ?? model.selectionStart
            },
            set: { transcriptTime in
                guard let playbackTime = model.playbackTime(forTranscriptTime: transcriptTime) else { return }
                ClipPlaybackManager.shared.seek(to: CMTime(seconds: playbackTime, preferredTimescale: 600))
            }
        )
    }

    private func playingBinding(for episode: BaseEpisode) -> Binding<Bool> {
        Binding(
            get: { ClipPlaybackManager.shared.isPlaying },
            set: { playing in
                if playing {
                    guard let start = model.playbackTime(forTranscriptTime: model.selectionStart),
                          let end = model.playbackTime(forTranscriptTime: model.selectionEnd) else { return }
                    clipTime.start = start
                    clipTime.end = end
                    clipTime.playback = start
                    ClipPlaybackManager.shared.play(episode: episode, clipTime: ObservedObject(wrappedValue: clipTime))
                } else {
                    ClipPlaybackManager.shared.stop()
                }
            }
        )
    }

    private func offsetBinding(_ binding: Binding<TimeInterval>) -> Binding<TimeInterval> {
        Binding(
            get: { binding.wrappedValue - model.windowStart },
            set: { binding.wrappedValue = $0 + model.windowStart }
        )
    }

    // MARK: - Tags

    @ViewBuilder private var tagsSection: some View {
        Section {
            if !model.tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(model.tags, id: \.self) { tag in
                        HighlightTagChip(tag: tag, showsRemove: true) {
                            model.removeTag(tag)
                        }
                    }
                }
            }

            TextField(L10n.highlightEditorTagPlaceholder, text: $model.tagInput)
                .font(style: .body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { model.addTag() }

            if !model.suggestedTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.suggestedTags.prefix(12), id: \.self) { tag in
                            HighlightTagChip(tag: tag, showsRemove: false) {
                                model.addTag(tag)
                            }
                        }
                    }
                }
            }
        } header: {
            Text(L10n.highlightEditorTagsSection)
                .font(style: .footnote, weight: .semibold)
        }
        .listRowBackground(AppTheme.color(for: .primaryUi02, theme: theme))
    }
}

/// A single tag pill; tapping either removes (in the editor's set) or adds
/// (from the suggestions row).
struct HighlightTagChip: View {
    @EnvironmentObject var theme: Theme

    let tag: String
    let showsRemove: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(tag)
                    .font(style: .footnote, weight: .medium)
                if showsRemove {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(AppTheme.color(for: .primaryUi05, theme: theme))
            )
            .foregroundStyle(AppTheme.color(for: .primaryText01, theme: theme))
        }
        .buttonStyle(.plain)
    }
}

/// Minimal wrapping layout for tag chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(proposal: proposal, subviews: subviews)
        for (subview, position) in zip(subviews, arrangement.positions) {
            subview.place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var origin = CGPoint.zero
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x > 0, origin.x + size.width > maxWidth {
                origin.x = 0
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(origin)
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, origin.x - spacing)
        }

        return (CGSize(width: totalWidth, height: origin.y + rowHeight), positions)
    }
}
