import SwiftUI
import PocketCastsServer

/// The Groups hub (Slice 13, ADR-0012): pending invites, the account's
/// circles and hubs, and discoverable public groups. Reached from the
/// Profile tab and the Explore Groups row.
struct SocialGroupsView: View {
    @EnvironmentObject private var theme: Theme
    @StateObject var viewModel: SocialGroupsViewModel
    @State private var showingCreate = false

    var body: some View {
        List {
            if !viewModel.invites.isEmpty {
                Section(header: Text(L10n.socialGroupInvitesTitle)) {
                    ForEach(viewModel.invites) { invite in
                        inviteRow(invite)
                    }
                }
            }

            Section(header: Text(L10n.socialGroupsMineTitle)) {
                if viewModel.groups.isEmpty, !viewModel.isLoading {
                    Text(L10n.socialGroupsEmpty)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                } else {
                    ForEach(viewModel.groups) { group in
                        NavigationLink(destination: GroupDetailView(viewModel: GroupDetailViewModel(groupId: group.id))
                            .environmentObject(theme)) {
                            groupRow(group)
                        }
                    }
                }
            }

            if !viewModel.discover.isEmpty {
                Section(header: Text(L10n.socialGroupsDiscoverTitle)) {
                    ForEach(viewModel.discover) { group in
                        NavigationLink(destination: GroupDetailView(viewModel: GroupDetailViewModel(
                            groupId: group.id,
                            onJoined: { viewModel.joinedGroup(id: $0) }
                        ))
                            .environmentObject(theme)) {
                            groupRow(group)
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.socialGroupsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(L10n.socialGroupCreateTitle)
            }
        }
        .sheet(isPresented: $showingCreate) {
            NavigationView {
                CreateGroupView { group in
                    showingCreate = false
                    if let group {
                        viewModel.inserted(group)
                    }
                }
                .environmentObject(theme)
            }
        }
        .task { await viewModel.load() }
    }

    private func groupRow(_ group: SocialGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: group.visibility == .public ? "person.3" : "lock")
                    .font(.caption)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                Text(group.title)
                    .font(.subheadline.weight(.medium))
            }
            HStack(spacing: 4) {
                Text(group.memberCount == 1 ? L10n.socialGroupMemberCountSingular : L10n.socialGroupMemberCount(group.memberCount))
                if !group.podcastTitle.isEmpty {
                    Text("·")
                    Text(group.podcastTitle)
                        .lineLimit(1)
                }
            }
            .font(.footnote)
            .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        }
        .padding(.vertical, 2)
    }

    private func inviteRow(_ invite: SocialGroup) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(invite.title)
                    .font(.subheadline.weight(.medium))
                Text(L10n.socialGroupInviteFrom("@" + invite.ownerHandle))
                    .font(.footnote)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            }
            Spacer()
            Button(L10n.socialFollowAccept) {
                Task { await viewModel.respond(to: invite, accept: true) }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderedProminent)
            Button(L10n.socialFollowDecline) {
                Task { await viewModel.respond(to: invite, accept: false) }
            }
            .font(.subheadline)
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 2)
    }
}

@MainActor
final class SocialGroupsViewModel: ObservableObject {
    @Published private(set) var groups: [SocialGroup] = []
    @Published private(set) var invites: [SocialGroup] = []
    @Published private(set) var discover: [SocialGroup] = []
    @Published private(set) var isLoading = true

    private var fixtureLoaded = false

    init() {}

    /// Fixture initializer for snapshots/previews; load() then no-ops.
    init(fixture: [SocialGroup], invites: [SocialGroup] = [], discover: [SocialGroup] = []) {
        groups = fixture
        self.invites = invites
        self.discover = discover
        isLoading = false
        fixtureLoaded = true
    }

    func load() async {
        guard !fixtureLoaded else { return }
        Analytics.track(.socialGroupsShown)
        if let overview = await ApiServerHandler.shared.fetchGroups() {
            groups = overview.groups
            invites = overview.invites
        }
        let mine = Set(groups.map(\.id))
        discover = await ApiServerHandler.shared.discoverGroups().filter { !mine.contains($0.id) }
        isLoading = false
    }

    func inserted(_ group: SocialGroup) {
        discover.removeAll { $0.id == group.id }
        groups.insert(group, at: 0)
    }

    func joinedGroup(id: Int64) {
        discover.removeAll { $0.id == id }
        guard !fixtureLoaded else { return }
        Task { await reconcileMembership() }
    }

    func respond(to invite: SocialGroup, accept: Bool) async {
        guard await ApiServerHandler.shared.respondToGroupInvite(id: invite.id, accept: accept) else { return }
        invites.removeAll { $0.id == invite.id }
        if accept {
            Analytics.track(.socialGroupJoined)
            discover.removeAll { $0.id == invite.id }
            await reconcileMembership()
        }
    }

    private func reconcileMembership() async {
        guard let overview = await ApiServerHandler.shared.fetchGroups() else { return }
        groups = overview.groups
        let mine = Set(groups.map(\.id))
        discover.removeAll { mine.contains($0.id) }
    }
}

@MainActor
final class CreateGroupSubmissionGate: ObservableObject {
    @Published private(set) var isSaving = false

    var canCancel: Bool { !isSaving }

    func perform(_ operation: () async -> SocialGroup?) async -> SocialGroup? {
        guard !isSaving else { return nil }
        isSaving = true
        defer { isSaving = false }
        return await operation()
    }
}

/// The create sheet: title, description, private/public, optional podcast
/// anchor (a fandom hub). The honest lifecycle consequence is stated in the
/// footer copy per ADR-0012.
struct CreateGroupView: View {
    @EnvironmentObject private var theme: Theme
    let onDone: (SocialGroup?) -> Void

    @State private var title = ""
    @State private var groupDescription = ""
    @State private var isPublic = false
    @StateObject private var submissionGate = CreateGroupSubmissionGate()
    @State private var failed = false

    /// Podcast anchor: set when creating from a podcast page.
    var anchorUuid = ""
    var anchorTitle = ""
    /// Hub creation entries (podcast page) start on the public setting.
    var startPublic = false

    init(
        onDone: @escaping (SocialGroup?) -> Void,
        anchorUuid: String = "",
        anchorTitle: String = "",
        startPublic: Bool = false
    ) {
        self.onDone = onDone
        self.anchorUuid = anchorUuid
        self.anchorTitle = anchorTitle
        self.startPublic = startPublic
    }

    var body: some View {
        Form {
            Section(footer: Text(isPublic ? L10n.socialGroupPublicFooter : L10n.socialGroupPrivateFooter)
                .font(.footnote)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))) {
                TextField(L10n.socialGroupTitlePlaceholder, text: $title)
                TextField(L10n.socialGroupDescriptionPlaceholder, text: $groupDescription, axis: .vertical)
                    .lineLimit(2 ... 4)
                Toggle(L10n.socialGroupPublicToggle, isOn: $isPublic)
            }
            if !anchorTitle.isEmpty {
                Section {
                    Label(anchorTitle, systemImage: "mic")
                        .font(.subheadline)
                }
            }
            if failed {
                Text(L10n.socialCommentSubmitFailed)
                    .font(.caption)
                    .foregroundColor(AppTheme.color(for: .support05, theme: theme))
            }
        }
        .onAppear {
            if startPublic { isPublic = true }
        }
        .navigationTitle(L10n.socialGroupCreateTitle)
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(!submissionGate.canCancel)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(L10n.cancel) { onDone(nil) }
                    .disabled(!submissionGate.canCancel)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if submissionGate.isSaving {
                    ProgressView()
                } else {
                    Button(L10n.done) {
                        Task { await save() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() async {
        guard !submissionGate.isSaving else { return }
        failed = false
        let group = await submissionGate.perform {
            await ApiServerHandler.shared.createGroup(
                title: title.trimmingCharacters(in: .whitespaces),
                description: groupDescription,
                visibility: isPublic ? .public : .private,
                podcastUuid: isPublic ? anchorUuid : "",
                podcastTitle: isPublic ? anchorTitle : "")
        }
        if let group {
            Analytics.track(.socialGroupCreated)
            onDone(group)
        } else {
            failed = true
        }
    }
}
