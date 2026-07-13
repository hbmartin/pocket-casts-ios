import SwiftUI
import WrappingHStack

/// The "Describe your playlist" sheet: a free-text description field, example
/// chips, and a generate button that opens the smart playlist preview with the
/// interpreted rules. Everything runs on device; a notice explains the simpler
/// fallback interpreter when Apple Intelligence isn't available.
struct PromptedPlaylistSheetView: View {
    @EnvironmentObject private var theme: Theme
    @ObservedObject var viewModel: PromptedPlaylistViewModel
    @FocusState private var promptFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.promptedPlaylistSheetTitle)
                .font(size: 22, style: .title2, weight: .bold)
                .foregroundStyle(AppTheme.color(for: .primaryText01, theme: theme))
                .padding(.top, 24)

            promptField

            exampleChips

            if !viewModel.unmatchedPodcastNames.isEmpty {
                noticeLabel(L10n.promptedPlaylistUnmatchedPodcasts(
                    viewModel.unmatchedPodcastNames.joined(separator: ", ")
                ))
            }

            if !viewModel.intelligenceAvailable {
                noticeLabel(L10n.promptedPlaylistFallbackNotice)
            }

            Spacer(minLength: 0)

            generateButton

            Text(L10n.promptedPlaylistIntelligenceFootnote)
                .font(.footnote)
                .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(AppTheme.color(for: .primaryUi01, theme: theme))
        .onAppear {
            promptFieldFocused = true
        }
    }

    private var promptField: some View {
        TextField(
            "",
            text: $viewModel.prompt,
            prompt: Text(L10n.promptedPlaylistPlaceholder)
                .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme)),
            axis: .vertical
        )
        .lineLimit(3 ... 6)
        .font(size: 15, style: .body, weight: .medium)
        .foregroundStyle(AppTheme.color(for: .primaryText01, theme: theme))
        .focused($promptFieldFocused)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(AppTheme.color(for: .primaryField03, theme: theme), lineWidth: 2)
        )
    }

    private var exampleChips: some View {
        WrappingHStack(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8, fitContentWidth: false) {
            ForEach(PromptedPlaylistViewModel.examplePrompts, id: \.self) { example in
                Button {
                    viewModel.prompt = example
                } label: {
                    Text(example)
                        .font(size: 13, style: .body, weight: .regular)
                        .foregroundStyle(AppTheme.color(for: .primaryText01, theme: theme))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(AppTheme.color(for: .primaryUi05, theme: theme))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func noticeLabel(_ text: String) -> some View {
        Text(text)
            .font(size: 13, style: .body, weight: .regular)
            .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var generateButton: some View {
        Button {
            Task {
                await viewModel.generate()
            }
        } label: {
            ZStack {
                Text(L10n.promptedPlaylistGenerate)
                    .font(size: 18, style: .headline, weight: .semibold)
                    .opacity(viewModel.isGenerating ? 0 : 1)
                if viewModel.isGenerating {
                    ProgressView()
                        .tint(AppTheme.color(for: .primaryInteractive02, theme: theme))
                }
            }
            .foregroundStyle(AppTheme.color(for: .primaryInteractive02, theme: theme))
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.color(for: .primaryInteractive01, theme: theme))
            )
        }
        .disabled(!viewModel.canGenerate)
        .opacity(viewModel.canGenerate || viewModel.isGenerating ? 1 : 0.4)
    }
}
