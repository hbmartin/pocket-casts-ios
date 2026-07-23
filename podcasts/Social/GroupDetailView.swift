import SwiftUI
import PocketCastsDataModel
import PocketCastsServer

/// One group's feed (Slice 13, ADR-0012): deliberate posts with threaded
/// replies (comment-tree semantics). Members compose; a public hub is
/// readable by anyone. The bell is the per-group opt-in new-post alert.
struct GroupDetailView: View {
    @EnvironmentObject private var theme: Theme
    @StateObject var viewModel: GroupDetailViewModel
    @FocusState private var composerFocused: Bool
    @State private var showingMembers = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            List {
                if let group = viewModel.group, !group.description.isEmpty {
                    Text(group.description)
                        .font(.footnote)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                }
                if viewModel.nodes.isEmpty, !viewModel.isLoading {
                    Text(L10n.socialGroupPostsEmpty)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                } else {
                    ForEach(viewModel.nodes) { node in
                        postRow(node)
                    }
                }
            }
            .listStyle(.plain)

            if viewModel.canPost {
                composer
            } else if viewModel.group?.visibility == .public, viewModel.group?.yourRole == GroupRole.none {
                joinBar
            }
        }
        .navigationTitle(viewModel.group?.title ?? L10n.socialGroupsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isMember {
                    Button {
                        Task { await viewModel.toggleAlerts() }
                    } label: {
                        Image(systemName: viewModel.group?.notifyPosts == true ? "bell.fill" : "bell")
                    }
                    .accessibilityLabel(L10n.socialGroupAlertToggle)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingMembers = true
                    } label: {
                        Label(L10n.socialGroupMembersTitle, systemImage: "person.2")
                    }
                    if viewModel.group?.yourRole == .member {
                        Button(role: .destructive) {
                            Task { await viewModel.leave() }
                        } label: {
                            Label(L10n.socialGroupLeave, systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                    if viewModel.group?.yourRole == .owner {
                        Button(role: .destructive) {
                            Task { await viewModel.deleteGroup() }
                        } label: {
                            Label(L10n.socialReviewDelete, systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(L10n.socialReportTitle, isPresented: $viewModel.showingReportPicker, titleVisibility: .visible) {
            ForEach(PublicProfileViewModel.reportReasons, id: \.1) { label, reason in
                Button(label) { Task { await viewModel.reportSelected(reason: reason) } }
            }
            Button(L10n.cancel, role: .cancel) {}
        }
        .sheet(isPresented: $showingMembers) {
            NavigationView {
                GroupMembersView(viewModel: viewModel)
                    .environmentObject(theme)
            }
        }
        .task { await viewModel.load() }
        .onChange(of: viewModel.departed) { _, departed in
            if departed { dismiss() }
        }
    }

    private func postRow(_ node: GroupPostNode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if node.post.removed {
                Text(L10n.socialCommentRemoved)
                    .font(.subheadline)
                    .italic()
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            } else {
                HStack(spacing: 6) {
                    Button {
                        SocialCoordinator.openPublicProfile(handle: node.post.handle)
                    } label: {
                        Text(node.post.displayName.isEmpty ? "@" + node.post.handle : node.post.displayName)
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    if let createdAt = node.post.createdAt {
                        Text(createdAt.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                    }
                }
                Text(node.post.text)
                    .font(.subheadline)
                    .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                if !node.post.episodeTitle.isEmpty {
                    Button {
                        NavigationManager.sharedManager.navigateTo(NavigationManager.episodePageKey,
                                                                   data: [NavigationManager.episodeUuidKey: node.post.episodeUuid,
                                                                          NavigationManager.podcastKey: node.post.podcastUuid])
                    } label: {
                        Label(node.post.episodeTitle, systemImage: "play.circle")
                            .font(.footnote)
                            .foregroundColor(AppTheme.color(for: .primaryInteractive01, theme: theme))
                    }
                    .buttonStyle(.plain)
                }
                if node.post.listId > 0, !node.post.listTitle.isEmpty {
                    Button {
                        SocialCoordinator.openSharedList(id: node.post.listId)
                    } label: {
                        Label(node.post.listTitle, systemImage: "list.bullet")
                            .font(.footnote)
                            .foregroundColor(AppTheme.color(for: .primaryInteractive01, theme: theme))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 14) {
                if viewModel.canPost {
                    Button(L10n.socialCommentReply) {
                        viewModel.beginReply(to: node.post)
                        composerFocused = true
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundColor(AppTheme.color(for: .primaryInteractive01, theme: theme))
                }
                if node.post.replyCount > 0, !viewModel.isExpanded(node.post.id) {
                    Button(node.post.replyCount == 1 ? L10n.socialCommentViewRepliesSingular : L10n.socialCommentViewRepliesPlural(node.post.replyCount)) {
                        Task { await viewModel.expand(node.post.id) }
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
            if viewModel.canModerate(node.post) {
                Button(role: .destructive) {
                    Task { await viewModel.delete(node.post) }
                } label: {
                    Label(L10n.socialReviewDelete, systemImage: "trash")
                }
            }
            if !node.post.removed, !viewModel.isOwn(node.post) {
                Button(role: .destructive) {
                    viewModel.reportTarget = node.post
                    viewModel.showingReportPicker = true
                } label: {
                    Label(L10n.socialReport, systemImage: "flag")
                }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let banner = viewModel.composerBanner {
                HStack {
                    Text(banner)
                        .font(.caption)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                    Spacer()
                    Button(L10n.cancel) { viewModel.cancelCompose() }
                        .font(.caption)
                }
            }
            if let attached = viewModel.attachedEpisodeTitle {
                HStack(spacing: 6) {
                    Label(attached, systemImage: "play.circle")
                        .font(.caption)
                        .lineLimit(1)
                    Button {
                        viewModel.detachEpisode()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            }
            HStack(spacing: 8) {
                TextField(L10n.socialGroupPostPlaceholder, text: $viewModel.composeText, axis: .vertical)
                    .lineLimit(1 ... 4)
                    .focused($composerFocused)
                    .textFieldStyle(.roundedBorder)
                if viewModel.canAttachEpisode {
                    Button {
                        viewModel.attachCurrentEpisode()
                    } label: {
                        Image(systemName: "play.circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.socialGroupAttachEpisode)
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
                    .disabled(viewModel.composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppTheme.color(for: .primaryUi02, theme: theme))
    }

    private var joinBar: some View {
        Button {
            Task { await viewModel.join() }
        } label: {
            Text(L10n.socialGroupJoin)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .padding(16)
    }
}

/// The members sheet: rows link nowhere for now; the owner kicks/bans.
struct GroupMembersView: View {
    @EnvironmentObject private var theme: Theme
    @ObservedObject var viewModel: GroupDetailViewModel

    var body: some View {
        List(viewModel.members) { member in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.displayName.isEmpty ? "@" + member.handle : member.displayName)
                        .font(.subheadline.weight(.medium))
                    Text("@" + member.handle)
                        .font(.footnote)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                }
                Spacer()
                if member.role == .owner {
                    Text(L10n.socialListRoleOwner)
                        .font(.caption)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                } else if viewModel.group?.yourRole == .owner {
                    Menu {
                        Button(role: .destructive) {
                            Task { await viewModel.kick(member, ban: false) }
                        } label: {
                            Label(L10n.socialGroupKick, systemImage: "person.badge.minus")
                        }
                        Button(role: .destructive) {
                            Task { await viewModel.kick(member, ban: true) }
                        } label: {
                            Label(L10n.socialGroupBan, systemImage: "nosign")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .navigationTitle(L10n.socialGroupMembersTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadMembers() }
    }
}

/// One visible row of the flattened post tree.
struct GroupPostNode: Identifiable {
    let post: GroupPost
    let depth: Int

    var id: Int64 { post.id }
}

@MainActor
final class GroupDetailViewModel: ObservableObject {
    let groupId: Int64

    @Published private(set) var group: SocialGroup?
    @Published private(set) var topLevel: [GroupPost] = []
    @Published private(set) var childrenByParent: [Int64: [GroupPost]] = [:]
    @Published private(set) var expanded: Set<Int64> = []
    @Published private(set) var members: [GroupMemberInfo] = []
    @Published private(set) var isLoading = true
    @Published var composeText = ""
    @Published private(set) var isSending = false
    @Published private(set) var attachedEpisodeTitle: String?
    @Published var showingReportPicker = false
    @Published private(set) var departed = false
    @Published var reportTarget: GroupPost?

    private var replyTarget: GroupPost?
    private var attachedEpisodeUuid = ""
    private var attachedPodcastUuid = ""
    private var fixtureLoaded = false

    init(groupId: Int64) {
        self.groupId = groupId
    }

    /// Fixture initializer for snapshots/previews; load() then no-ops.
    init(fixture: [GroupPost], group: SocialGroup, children: [Int64: [GroupPost]] = [:], expanded: Set<Int64> = []) {
        groupId = group.id
        self.group = group
        topLevel = fixture
        childrenByParent = children
        self.expanded = expanded
        isLoading = false
        fixtureLoaded = true
    }

    var isMember: Bool {
        group?.yourRole == .member || group?.yourRole == .owner
    }

    var canPost: Bool { isMember }

    var nodes: [GroupPostNode] {
        var result: [GroupPostNode] = []
        func append(_ post: GroupPost, depth: Int) {
            result.append(GroupPostNode(post: post, depth: depth))
            if expanded.contains(post.id), let children = childrenByParent[post.id] {
                for child in children {
                    append(child, depth: depth + 1)
                }
            }
        }
        for post in topLevel {
            append(post, depth: 0)
        }
        return result
    }

    func isExpanded(_ id: Int64) -> Bool { expanded.contains(id) }

    func load() async {
        guard !fixtureLoaded else { return }
        Analytics.track(.socialGroupOpened)
        if let page = await ApiServerHandler.shared.fetchGroupPosts(groupId: groupId) {
            topLevel = page.posts
            group = page.group
        }
        isLoading = false
    }

    func expand(_ id: Int64) async {
        if childrenByParent[id] == nil {
            guard let page = await ApiServerHandler.shared.fetchGroupPosts(groupId: groupId, parentId: id) else { return }
            childrenByParent[id] = page.posts
        }
        expanded.insert(id)
    }

    func loadMembers() async {
        guard !fixtureLoaded else { return }
        members = await ApiServerHandler.shared.fetchGroupMembers(groupId: groupId) ?? []
    }

    // MARK: - Composing

    var composerBanner: String? {
        replyTarget.map { L10n.socialCommentReplyingTo("@" + $0.handle) }
    }

    var canAttachEpisode: Bool {
        replyTarget == nil && PlaybackManager.shared.currentEpisode() != nil
    }

    func beginReply(to post: GroupPost) {
        replyTarget = post
        detachEpisode()
    }

    func cancelCompose() {
        replyTarget = nil
        composeText = ""
        detachEpisode()
    }

    func attachCurrentEpisode() {
        guard let episode = PlaybackManager.shared.currentEpisode() else { return }
        attachedEpisodeUuid = episode.uuid
        attachedPodcastUuid = episode.parentIdentifier()
        attachedEpisodeTitle = episode.displayableTitle()
    }

    func detachEpisode() {
        attachedEpisodeUuid = ""
        attachedPodcastUuid = ""
        attachedEpisodeTitle = nil
    }

    func send() async {
        let text = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        let parentId = replyTarget?.id ?? 0
        let submitted = await ApiServerHandler.shared.submitGroupPost(
            groupId: groupId, parentId: parentId, text: text,
            episodeUuid: parentId == 0 ? attachedEpisodeUuid : "",
            podcastUuid: parentId == 0 ? attachedPodcastUuid : "",
            episodeTitle: parentId == 0 ? (attachedEpisodeTitle ?? "") : "")
        if submitted != nil {
            Analytics.track(.socialGroupPosted)
            if let replyTarget {
                childrenByParent[replyTarget.id] = nil
                await expand(replyTarget.id)
            }
            if let page = await ApiServerHandler.shared.fetchGroupPosts(groupId: groupId) {
                topLevel = page.posts
                group = page.group
            }
            cancelCompose()
        }
        isSending = false
    }

    // MARK: - Actions

    func isOwn(_ post: GroupPost) -> Bool {
        !post.removed && !post.userId.isEmpty && post.userId == SocialIdentityStore.cachedProfile?.userId
    }

    /// The author tombstones their own post; the owner tombstones anyone's.
    func canModerate(_ post: GroupPost) -> Bool {
        !post.removed && (isOwn(post) || group?.yourRole == .owner)
    }

    func delete(_ post: GroupPost) async {
        guard await ApiServerHandler.shared.deleteGroupPost(id: post.id) else { return }
        if let page = await ApiServerHandler.shared.fetchGroupPosts(groupId: groupId) {
            topLevel = page.posts
        }
        // Re-fetch the sibling page so an expanded branch stays expanded
        // (nil-ing the cache while the parent stays in `expanded` hid the
        // surviving replies with no way back — QA review finding).
        if post.parentId > 0 {
            childrenByParent[post.parentId] = nil
            if expanded.contains(post.parentId) {
                await expand(post.parentId)
            }
        }
    }

    func reportSelected(reason: SocialReportReason) async {
        guard let target = reportTarget else { return }
        Analytics.track(.socialProfileReported)
        _ = await ApiServerHandler.shared.reportUser(targetUserId: target.userId,
                                                     reason: reason,
                                                     context: "group-post:\(target.id)")
        reportTarget = nil
    }

    func join() async {
        guard await ApiServerHandler.shared.joinGroup(id: groupId) else { return }
        Analytics.track(.socialGroupJoined)
        if let page = await ApiServerHandler.shared.fetchGroupPosts(groupId: groupId) {
            topLevel = page.posts
            group = page.group
        }
    }

    func leave() async {
        guard await ApiServerHandler.shared.leaveGroup(id: groupId) else { return }
        departed = true
    }

    func deleteGroup() async {
        guard await ApiServerHandler.shared.deleteGroup(id: groupId) else { return }
        departed = true
    }

    func toggleAlerts() async {
        guard let group else { return }
        let enable = !group.notifyPosts
        guard await ApiServerHandler.shared.setGroupAlert(id: groupId, enabled: enable) else { return }
        Analytics.track(.socialGroupAlertChanged)
        if let page = await ApiServerHandler.shared.fetchGroupPosts(groupId: groupId) {
            self.group = page.group
        }
    }

    func kick(_ member: GroupMemberInfo, ban: Bool) async {
        guard await ApiServerHandler.shared.kickFromGroup(id: groupId, handle: member.handle, ban: ban) else { return }
        members.removeAll { $0.handle == member.handle }
    }
}
