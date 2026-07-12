import Combine
import SwiftUI
import UIKit

/// Full-screen, typography-first presentation of a transcript. Follow-along
/// highlighting reuses the same fingerprint gating as the transcript view
/// controller, driven here by a ~4 Hz timer instead of a second CADisplayLink.
struct TranscriptReaderView: View {

    @ObservedObject var viewModel: TranscriptReaderViewModel
    let canShareClip: Bool
    let onShareQuote: (String) -> Void
    let onShareClip: (_ start: TimeInterval, _ end: TimeInterval) -> Void
    let onClose: () -> Void

    @EnvironmentObject private var theme: Theme

    @State private var textSize = Settings.transcriptReaderTextSize
    @State private var useSerifFont = Settings.transcriptReaderUsesSerifFont
    @State private var isSearchVisible = false
    @State private var searchText = ""
    @State private var lastAutoScrolledBlockID: Int?
    @State private var searchDebounce = Debounce(delay: Constants.defaultDebounceTime)
    @FocusState private var isSearchFieldFocused: Bool

    /// ~4 Hz follow-along tick; the per-tick work is a cheap no-op when the
    /// current cue hasn't changed.
    private let followTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private enum Layout {
        static let contentMaxWidth: CGFloat = 720
        /// Keep the active cue ~30% from the top, matching the VC's anchor.
        static let followAnchor = UnitPoint(x: 0.5, y: 0.3)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isSearchVisible {
                searchBar
            }
            ZStack(alignment: .bottom) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(viewModel.blocks) { block in
                                blockView(block)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 48)
                        .frame(maxWidth: Layout.contentMaxWidth, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                    .onScrollPhaseChange { _, newPhase in
                        if newPhase == .tracking || newPhase == .interacting {
                            viewModel.noteUserScrolled()
                        }
                    }
                    .onReceive(followTimer) { _ in
                        handleFollowTick(proxy: proxy)
                    }
                    .onChange(of: viewModel.isFollowing) { _, isFollowing in
                        if isFollowing {
                            // Catch up immediately instead of waiting for a cue change.
                            lastAutoScrolledBlockID = nil
                        }
                    }
                    .onChange(of: viewModel.currentMatchIndex) {
                        scrollToCurrentMatch(proxy: proxy)
                    }
                    .onChange(of: viewModel.matches) {
                        scrollToCurrentMatch(proxy: proxy)
                    }
                    .onAppear {
                        viewModel.refreshCurrentCue()
                        if let blockID = viewModel.currentCueBlockID {
                            lastAutoScrolledBlockID = blockID
                            proxy.scrollTo(blockID, anchor: Layout.followAnchor)
                        }
                    }
                }

                if showsResumePill {
                    resumeFollowingPill
                }
            }
        }
        .background(AppTheme.color(for: .primaryUi01, theme: theme).ignoresSafeArea())
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 20) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .medium))
            }
            .accessibilityLabel(L10n.close)

            if let title = viewModel.episodeTitle {
                Text(title)
                    .font(.footnote)
                    .lineLimit(1)
                    .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Spacer()
            }

            Button {
                textSize = textSize.next
                Settings.transcriptReaderTextSize = textSize
            } label: {
                Text(verbatim: "Aa")
                    .font(.system(size: 17, weight: .semibold, design: fontDesign))
            }
            .accessibilityLabel(L10n.transcriptReaderTextSize)
            .contextMenu {
                Toggle(isOn: serifFontBinding) {
                    Text(L10n.transcriptReaderFontSerif)
                }
            }

            Button {
                toggleSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
            }
            .accessibilityLabel(L10n.search)
        }
        .foregroundStyle(AppTheme.color(for: .primaryIcon02, theme: theme))
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var serifFontBinding: Binding<Bool> {
        Binding {
            useSerifFont
        } set: { newValue in
            useSerifFont = newValue
            Settings.transcriptReaderUsesSerifFont = newValue
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.color(for: .primaryIcon02, theme: theme))

            TextField(L10n.search, text: $searchText)
                .focused($isSearchFieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundStyle(AppTheme.color(for: .primaryText01, theme: theme))
                .onChange(of: searchText) { _, newValue in
                    searchDebounce.call {
                        viewModel.search(term: newValue)
                    }
                }

            if !searchText.isEmpty {
                Text(matchCountLabel)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
            }

            Button(action: viewModel.previousMatch) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .semibold))
            }
            .disabled(viewModel.matches.isEmpty)

            Button(action: viewModel.nextMatch) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
            }
            .disabled(viewModel.matches.isEmpty)

            Button(L10n.done) {
                toggleSearch()
            }
            .font(.callout.weight(.medium))
        }
        .foregroundStyle(AppTheme.color(for: .primaryInteractive01, theme: theme))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.color(for: .primaryField01, theme: theme), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var matchCountLabel: String {
        guard !viewModel.matches.isEmpty else { return "0" }
        return L10n.searchResults(viewModel.currentMatchIndex + 1, viewModel.matches.count)
    }

    private func toggleSearch() {
        if isSearchVisible {
            isSearchVisible = false
            searchText = ""
            searchDebounce.cancel()
            viewModel.clearSearch()
        } else {
            isSearchVisible = true
            isSearchFieldFocused = true
        }
    }

    // MARK: - Blocks

    @ViewBuilder
    private func blockView(_ block: TranscriptReaderBlock) -> some View {
        switch block.kind {
        case .speaker(let name):
            Text(highlightedText(for: block))
                .font(.system(size: scaledSize(for: textSize.pointSize * 0.76), weight: .semibold, design: fontDesign).smallCaps())
                .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                .padding(.top, 16)
                .id(block.id)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(name)

        case .paragraph(let cueIndex):
            let isCurrent = viewModel.currentCueBlockID == block.id
            let bodySize = scaledSize(for: textSize.pointSize)
            let paragraph = Text(highlightedText(for: block))
                .font(.system(size: bodySize, design: fontDesign))
                .lineSpacing(bodySize * 0.3)
                .foregroundStyle(
                    isCurrent
                        ? AppTheme.color(for: .primaryInteractive01, theme: theme)
                        : AppTheme.color(for: .primaryText01, theme: theme)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(block.id)

            if let cueIndex {
                paragraph
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleTap(cueIndex: cueIndex)
                    }
                    .contextMenu {
                        Button {
                            if let quote = viewModel.quoteText(forBlock: block.id) {
                                onShareQuote(quote)
                            }
                        } label: {
                            Label(L10n.transcriptReaderShareQuote, systemImage: "quote.opening")
                        }

                        if canShareClip, let range = viewModel.clipRange(forBlock: block.id) {
                            Button {
                                onShareClip(range.start, range.end)
                            } label: {
                                Label(L10n.transcriptReaderShareAsClip, systemImage: "scissors")
                            }
                        }
                    }
            } else {
                paragraph
                    .textSelection(.enabled)
            }
        }
    }

    /// The block's text with the existing transcript search highlight style
    /// applied to any matches inside it.
    private func highlightedText(for block: TranscriptReaderBlock) -> AttributedString {
        var attributed = AttributedString(block.text)
        guard !viewModel.searchTerm.isEmpty, let blockMatches = viewModel.matchesByBlock[block.id] else {
            return attributed
        }
        for match in blockMatches {
            guard let range = attributedRange(for: match.characterRange, in: attributed) else { continue }
            let style = TranscriptSearchHighlightStyle.attributes(
                showFromEpisode: true,
                isCurrent: match.matchIndex == viewModel.currentMatchIndex
            )
            if let background = style[.backgroundColor] as? UIColor {
                attributed[range].backgroundColor = Color(uiColor: background)
            }
            if let foreground = style[.foregroundColor] as? UIColor {
                attributed[range].foregroundColor = Color(uiColor: foreground)
            }
        }
        return attributed
    }

    /// Converts character offsets (as produced by `KMPSearch`) into an
    /// `AttributedString` range, clamped to the text's bounds.
    private func attributedRange(for characterRange: Range<Int>, in attributed: AttributedString) -> Range<AttributedString.Index>? {
        let characters = attributed.characters
        guard characterRange.lowerBound >= 0,
              let start = characters.index(characters.startIndex, offsetBy: characterRange.lowerBound, limitedBy: characters.endIndex),
              let end = characters.index(start, offsetBy: characterRange.count, limitedBy: characters.endIndex),
              start < end else {
            return nil
        }
        return start ..< end
    }

    // MARK: - Follow-along

    private var showsResumePill: Bool {
        !viewModel.isFollowing && viewModel.currentCueBlockID != nil && !isSearchVisible
    }

    private var resumeFollowingPill: some View {
        Button {
            viewModel.resumeFollowing()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 12, weight: .semibold))
                Text(L10n.transcriptReaderResumeFollowing)
                    .font(.footnote.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(AppTheme.color(for: .primaryInteractive01, theme: theme), in: Capsule())
            .foregroundStyle(AppTheme.color(for: .primaryInteractive02, theme: theme))
        }
        .padding(.bottom, 20)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func handleFollowTick(proxy: ScrollViewProxy) {
        viewModel.refreshCurrentCue()
        guard viewModel.isFollowing, !isSearchVisible,
              let blockID = viewModel.currentCueBlockID,
              blockID != lastAutoScrolledBlockID else {
            return
        }
        lastAutoScrolledBlockID = blockID
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(blockID, anchor: Layout.followAnchor)
        }
    }

    private func scrollToCurrentMatch(proxy: ScrollViewProxy) {
        guard let match = viewModel.currentMatch else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(match.blockID, anchor: .center)
        }
    }

    // MARK: - Seeking

    private func handleTap(cueIndex: Int) {
        let outcome = viewModel.seek(toCueIndex: cueIndex)
        if outcome == .downloadRequiredHint {
            Toast.show(L10n.transcriptTapToSeekStreamingUnavailable)
        }
    }

    // MARK: - Typography

    private var fontDesign: Font.Design {
        useSerifFont ? .serif : .default
    }

    /// Dynamic Type-aware size: scales the reader's base size with the user's
    /// preferred body text size.
    private func scaledSize(for base: CGFloat) -> CGFloat {
        UIFontMetrics(forTextStyle: .body).scaledValue(for: base)
    }
}
