import SwiftUI
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils

/// The episode's comment tree (Slice 6, ADR-0010): one list, two lenses — this
/// screen shows every top-level comment newest-first (timestamped ones carry a
/// seek chip; the player renders the same nodes as scrubber pins). Branches
/// expand on demand to any depth; tombstones keep their place. Composing a
/// top-level comment needs ≥25% of the episode played (server-enforced too);
/// replies are ungated. Edits are offered only inside the grace window.
struct EpisodeCommentsView: View {
    @EnvironmentObject var theme: Theme
    @StateObject var viewModel: EpisodeCommentsViewModel
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List {
                    if viewModel.nodes.isEmpty, !viewModel.isLoading {
                        Section {
                            Text(L10n.socialCommentsEmpty)
                                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                        }
                    } else {
                        ForEach(viewModel.nodes) { node in
                            commentRow(node)
                                .id(node.comment.id)
                        }
                        if viewModel.canLoadMore {
                            Button(L10n.socialReviewsLoadMore) {
                                Task { await viewModel.loadMore() }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .onChange(of: viewModel.scrollTarget) { _, target in
                    if let target {
                        withAnimation { proxy.scrollTo(target, anchor: .center) }
                        viewModel.scrollTarget = nil
                    }
                }
            }

            composer
        }
        .navigationTitle(L10n.socialCommentsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(L10n.socialReportTitle, isPresented: $viewModel.showingReportPicker, titleVisibility: .visible) {
            ForEach(PublicProfileViewModel.reportReasons, id: \.1) { label, reason in
                Button(label) { Task { await viewModel.reportSelected(reason: reason) } }
            }
            Button(L10n.cancel, role: .cancel) {}
        }
        .task { await viewModel.load() }
    }

    // MARK: - Rows

    private func commentRow(_ node: CommentNode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if node.comment.removed {
                Text(L10n.socialCommentRemoved)
                    .font(.subheadline)
                    .italic()
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            } else {
                HStack(spacing: 6) {
                    Button {
                        SocialCoordinator.openPublicProfile(handle: node.comment.handle)
                    } label: {
                        Text(node.comment.displayName.isEmpty ? "@" + node.comment.handle : node.comment.displayName)
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                    }
                    .buttonStyle(.plain)
                    if let seconds = node.comment.timestampSeconds {
                        Button {
                            viewModel.seek(to: seconds)
                        } label: {
                            Text("@ " + TimeFormatter.shared.playTimeFormat(time: TimeInterval(seconds)))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(AppTheme.color(for: .primaryUi05, theme: theme)))
                        }
                        .buttonStyle(.plain)
                    }
                    if node.comment.edited {
                        Text(L10n.socialCommentEdited)
                            .font(.caption)
                            .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                    }
                    Spacer(minLength: 0)
                    if let createdAt = node.comment.createdAt {
                        Text(createdAt.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                    }
                }
                if !node.comment.quote.isEmpty {
                    // The transcript quote renders from stored text alone —
                    // never resolved through the (advisory) segment ref.
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(AppTheme.color(for: .primaryInteractive01, theme: theme))
                            .frame(width: 3)
                        Text(node.comment.quote)
                            .font(.footnote)
                            .italic()
                            .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let seconds = node.comment.timestampSeconds {
                            viewModel.seek(to: seconds)
                        }
                    }
                }
                Text(node.comment.text)
                    .font(.subheadline)
                    .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
            }

            HStack(spacing: 14) {
                Button(L10n.socialCommentReply) {
                    viewModel.beginReply(to: node.comment)
                    composerFocused = true
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundColor(AppTheme.color(for: .primaryInteractive01, theme: theme))

                if node.comment.replyCount > 0, !viewModel.isExpanded(node.comment.id) {
                    Button(node.comment.replyCount == 1 ? L10n.socialCommentViewRepliesSingular : L10n.socialCommentViewReplies(node.comment.replyCount)) {
                        Task { await viewModel.expand(node.comment.id) }
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(AppTheme.color(for: .primaryInteractive01, theme: theme))
                }
            }
            .padding(.top, 2)
        }
        .padding(.leading, CGFloat(min(node.depth, 4)) * 16)
        .padding(.vertical, 2)
        .contextMenu {
            if viewModel.isOwn(node.comment) {
                if viewModel.isEditable(node.comment) {
                    Button {
                        viewModel.beginEdit(of: node.comment)
                        composerFocused = true
                    } label: {
                        Label(L10n.socialReviewEdit, systemImage: "pencil")
                    }
                }
                Button(role: .destructive) {
                    Task { await viewModel.delete(node.comment) }
                } label: {
                    Label(L10n.socialReviewDelete, systemImage: "trash")
                }
            } else if !node.comment.removed {
                Button(role: .destructive) {
                    viewModel.reportTarget = node.comment
                    viewModel.showingReportPicker = true
                } label: {
                    Label(L10n.socialReport, systemImage: "flag")
                }
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let banner = viewModel.composerBanner {
                HStack {
                    Text(banner)
                        .font(.caption)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                    Spacer()
                    Button(L10n.cancel) { viewModel.cancelComposeMode() }
                        .font(.caption)
                }
            }
            if let error = viewModel.composeError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(AppTheme.color(for: .support05, theme: theme))
            }
            if let quote = viewModel.pendingQuote, viewModel.composerBanner == nil {
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(AppTheme.color(for: .primaryInteractive01, theme: theme))
                        .frame(width: 3)
                    Text(quote.text)
                        .font(.caption)
                        .italic()
                        .lineLimit(2)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                    Spacer(minLength: 0)
                    Button {
                        viewModel.removeQuote()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.socialCommentQuoteRemove)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                TextField(viewModel.composerPlaceholder, text: $viewModel.composeText, axis: .vertical)
                    .lineLimit(1 ... 4)
                    .focused($composerFocused)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!viewModel.canCompose)
                if viewModel.canAttachTimestamp {
                    Button {
                        viewModel.toggleTimestamp()
                    } label: {
                        Image(systemName: viewModel.attachTimestamp ? "clock.fill" : "clock")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.socialCommentAttachTimestamp)
                }
                if viewModel.isSending {
                    ProgressView()
                } else {
                    Button {
                        Task { await viewModel.send() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canCompose || viewModel.composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if !viewModel.canCompose {
                Text(viewModel.composeGateHint)
                    .font(.caption)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppTheme.color(for: .primaryUi02, theme: theme))
    }
}

/// One visible row of the flattened tree.
struct CommentNode: Identifiable {
    let comment: SocialComment
    let depth: Int

    var id: Int64 { comment.id }
}

/// A transcript quote staged in the composer (Slice 12). The quote text is
/// self-contained rendering truth; source/segment are the advisory ref. A nil
/// timestamp means "stamp the current playback position at send" (the
/// auto-quote path); the transcript reader presets the line's own time.
struct PendingTranscriptQuote: Equatable {
    let text: String
    let source: Int
    let segment: Int
    let timestampSeconds: Int?

    /// Wire values for `quote_source` (0 = unspecified). Qualified: the app
    /// target has an unrelated player-side `TranscriptSource` enum.
    static func wireSource(_ source: PocketCastsDataModel.TranscriptSource) -> Int {
        switch source {
        case .provided: 1
        case .generated: 2
        }
    }
}

@MainActor
final class EpisodeCommentsViewModel: ObservableObject {
    let episodeUuid: String
    let podcastUuid: String
    let episodeTitle: String
    let podcastTitle: String

    /// Seed gate (≥25% played), mirrored client-side; the server re-checks.
    let canSeed: Bool
    /// A Moment pin tapped on the player opens its subtree directly.
    let focusCommentId: Int64?

    @Published private(set) var topLevel: [SocialComment] = []
    @Published private(set) var childrenByParent: [Int64: [SocialComment]] = [:]
    @Published private(set) var expanded: Set<Int64> = []
    @Published private(set) var total = 0
    @Published private(set) var isLoading = true
    @Published var composeText = ""
    @Published var attachTimestamp = false
    @Published private(set) var pendingQuote: PendingTranscriptQuote?
    @Published private(set) var isSending = false
    @Published private(set) var composeError: String?
    @Published var showingReportPicker = false
    @Published var reportTarget: SocialComment?
    @Published var scrollTarget: Int64?

    private var replyTarget: SocialComment?
    private var editTarget: SocialComment?
    private var fixtureLoaded = false
    private static let pageSize = 50

    init(episodeUuid: String, podcastUuid: String, episodeTitle: String = "", podcastTitle: String = "",
         canSeed: Bool, focusCommentId: Int64? = nil, presetQuote: PendingTranscriptQuote? = nil) {
        self.episodeUuid = episodeUuid
        self.podcastUuid = podcastUuid
        self.episodeTitle = episodeTitle
        self.podcastTitle = podcastTitle
        self.canSeed = canSeed
        self.focusCommentId = focusCommentId
        if let presetQuote {
            pendingQuote = presetQuote
            attachTimestamp = true
        }
    }

    /// Fixture initializer for snapshots/previews; load() then no-ops.
    init(fixture: [SocialComment], children: [Int64: [SocialComment]] = [:], expanded: Set<Int64> = [], canSeed: Bool = true) {
        episodeUuid = "fixture"
        podcastUuid = ""
        episodeTitle = ""
        podcastTitle = ""
        self.canSeed = canSeed
        focusCommentId = nil
        topLevel = fixture
        childrenByParent = children
        self.expanded = expanded
        total = fixture.count
        isLoading = false
        fixtureLoaded = true
    }

    // MARK: - Tree

    var nodes: [CommentNode] {
        var result: [CommentNode] = []
        func append(_ comment: SocialComment, depth: Int) {
            result.append(CommentNode(comment: comment, depth: depth))
            if expanded.contains(comment.id), let children = childrenByParent[comment.id] {
                for child in children {
                    append(child, depth: depth + 1)
                }
            }
        }
        for comment in topLevel {
            append(comment, depth: 0)
        }
        return result
    }

    var canLoadMore: Bool { topLevel.count < total }

    func isExpanded(_ id: Int64) -> Bool { expanded.contains(id) }

    func load() async {
        guard !fixtureLoaded else { return }
        Analytics.track(.socialCommentsOpened)
        if let page = await ApiServerHandler.shared.fetchEpisodeComments(episodeUuid: episodeUuid) {
            topLevel = page.comments
            total = page.total
        }
        isLoading = false
        if let focusCommentId {
            await expand(focusCommentId)
            scrollTarget = focusCommentId
        }
    }

    func loadMore() async {
        guard let page = await ApiServerHandler.shared.fetchEpisodeComments(episodeUuid: episodeUuid, offset: topLevel.count) else { return }
        topLevel.append(contentsOf: page.comments)
        total = page.total
    }

    func expand(_ id: Int64) async {
        if childrenByParent[id] == nil {
            guard let page = await ApiServerHandler.shared.fetchCommentReplies(parentId: id) else { return }
            childrenByParent[id] = page.comments
        }
        expanded.insert(id)
    }

    // MARK: - Composing

    var canCompose: Bool { canSeed || replyTarget != nil || editTarget != nil }

    var composeGateHint: String { L10n.socialCommentsGateHint }

    var composerPlaceholder: String { L10n.socialCommentPlaceholder }

    var composerBanner: String? {
        if let editTarget {
            _ = editTarget
            return L10n.socialCommentEditingBanner
        }
        if let replyTarget {
            return L10n.socialCommentReplyingTo("@" + replyTarget.handle)
        }
        return nil
    }

    /// Timestamp attach is offered for new top-level comments while this
    /// episode is the one playing.
    var canAttachTimestamp: Bool {
        replyTarget == nil && editTarget == nil && canSeed
            && PlaybackManager.shared.currentEpisode()?.uuid == episodeUuid
    }

    /// The clock toggle. Turning the timestamp on also auto-grabs the current
    /// transcript line as a quote when the local index has one (Slice 12);
    /// turning it off drops both.
    func toggleTimestamp() {
        attachTimestamp.toggle()
        if attachTimestamp {
            Task { await autoQuoteCurrentLine() }
        } else {
            pendingQuote = nil
        }
    }

    func removeQuote() {
        pendingQuote = nil
    }

    private func autoQuoteCurrentLine() async {
        guard pendingQuote == nil else { return }
        let uuid = episodeUuid
        let time = PlaybackManager.shared.currentTime()
        let found: (TranscriptSearchSegment, PocketCastsDataModel.TranscriptSource)? = await Task.detached(priority: .userInitiated) {
            let search = DataManager.sharedManager.transcriptSearch
            for source in [PocketCastsDataModel.TranscriptSource.generated, .provided] {
                let segments = search.segments(episodeUuid: uuid, source: source)
                if let line = segments.last(where: { $0.startTime <= time && time < ($0.endTime ?? .greatestFiniteMagnitude) })
                    ?? segments.last(where: { $0.startTime <= time }) {
                    return (line, source)
                }
            }
            return nil
        }.value
        // The toggle may have flipped off (or a quote landed) while we read.
        guard attachTimestamp, pendingQuote == nil, let (line, source) = found else { return }
        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        pendingQuote = PendingTranscriptQuote(text: text,
                                              source: PendingTranscriptQuote.wireSource(source),
                                              segment: line.index,
                                              timestampSeconds: nil)
    }

    func beginReply(to comment: SocialComment) {
        editTarget = nil
        replyTarget = comment
        composeError = nil
    }

    func beginEdit(of comment: SocialComment) {
        replyTarget = nil
        editTarget = comment
        composeText = comment.text
        composeError = nil
    }

    func cancelComposeMode() {
        replyTarget = nil
        editTarget = nil
        composeText = ""
        composeError = nil
        pendingQuote = nil
    }

    func send() async {
        let text = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        composeError = nil

        if let editTarget {
            if await ApiServerHandler.shared.editComment(id: editTarget.id, text: text) {
                await reloadPreservingExpansion()
                cancelComposeMode()
            } else {
                composeError = L10n.socialCommentEditFailed
            }
            isSending = false
            return
        }

        let parentId = replyTarget?.id ?? 0
        // Guard the live stamp against playback moving on to another episode
        // while the composer was open (QA review finding).
        let isThisEpisodePlaying = PlaybackManager.shared.currentEpisode()?.uuid == episodeUuid
        var timestamp: Int? = (parentId == 0 && attachTimestamp && isThisEpisodePlaying)
            ? Int(PlaybackManager.shared.currentTime()) : nil
        // A preset quote (transcript reader) anchors to its own line's time.
        let quote = parentId == 0 ? pendingQuote : nil
        if let presetTime = quote?.timestampSeconds {
            timestamp = presetTime
        }
        let submitted = await ApiServerHandler.shared.submitComment(
            episodeUuid: episodeUuid, podcastUuid: podcastUuid,
            episodeTitle: episodeTitle, podcastTitle: podcastTitle,
            text: text, parentId: parentId, timestampSeconds: timestamp,
            quote: timestamp != nil ? (quote?.text ?? "") : "",
            quoteSource: quote?.source ?? 0, quoteSegment: quote?.segment ?? 0)
        if submitted != nil {
            Analytics.track(.socialCommentSubmitted)
            if let replyTarget {
                childrenByParent[replyTarget.id] = nil
                await expand(replyTarget.id)
                bumpReplyCount(of: replyTarget.id)
            }
            await reloadPreservingExpansion()
            cancelComposeMode()
            attachTimestamp = false
        } else {
            composeError = L10n.socialCommentSubmitFailed
        }
        isSending = false
    }

    // MARK: - Row actions

    func isOwn(_ comment: SocialComment) -> Bool {
        !comment.removed && comment.userId == SocialIdentityStore.cachedProfile?.userId
    }

    /// Mirror of the server's grace window: unreplied and < 5 minutes old.
    func isEditable(_ comment: SocialComment) -> Bool {
        guard isOwn(comment), comment.replyCount == 0, let createdAt = comment.createdAt else { return false }
        return Date().timeIntervalSince(createdAt) < 5 * 60
    }

    func delete(_ comment: SocialComment) async {
        guard await ApiServerHandler.shared.deleteComment(id: comment.id) else { return }
        await reloadPreservingExpansion()
    }

    func reportSelected(reason: SocialReportReason) async {
        guard let target = reportTarget else { return }
        Analytics.track(.socialProfileReported)
        _ = await ApiServerHandler.shared.reportUser(targetUserId: target.userId,
                                                     reason: reason,
                                                     context: "comment:\(target.id)")
    }

    func seek(to seconds: Int) {
        NavigationManager.sharedManager.navigateTo(NavigationManager.episodePageKey,
                                                   data: [NavigationManager.episodeUuidKey: episodeUuid,
                                                          NavigationManager.podcastKey: podcastUuid,
                                                          NavigationManager.episodeTimestamp: TimeInterval(seconds)])
    }

    // MARK: - Helpers

    private func bumpReplyCount(of id: Int64) {
        if let index = topLevel.firstIndex(where: { $0.id == id }) {
            topLevel[index] = adjusted(topLevel[index])
        }
        for (parent, children) in childrenByParent {
            if let index = children.firstIndex(where: { $0.id == id }) {
                var updated = children
                updated[index] = adjusted(children[index])
                childrenByParent[parent] = updated
            }
        }
    }

    private func adjusted(_ comment: SocialComment) -> SocialComment {
        SocialComment(id: comment.id, parentId: comment.parentId, userId: comment.userId,
                      handle: comment.handle, displayName: comment.displayName, text: comment.text,
                      timestampSeconds: comment.timestampSeconds,
                      quote: comment.quote, quoteSource: comment.quoteSource, quoteSegment: comment.quoteSegment,
                      createdAt: comment.createdAt,
                      edited: comment.edited, removed: comment.removed, replyCount: comment.replyCount + 1,
                      episodeUuid: comment.episodeUuid, podcastUuid: comment.podcastUuid,
                      episodeTitle: comment.episodeTitle, podcastTitle: comment.podcastTitle)
    }

    private func reloadPreservingExpansion() async {
        guard !fixtureLoaded else { return }
        if let page = await ApiServerHandler.shared.fetchEpisodeComments(episodeUuid: episodeUuid, limit: max(Self.pageSize, topLevel.count)) {
            topLevel = page.comments
            total = page.total
        }
        for id in expanded {
            if let page = await ApiServerHandler.shared.fetchCommentReplies(parentId: id) {
                childrenByParent[id] = page.comments
            }
        }
    }
}
