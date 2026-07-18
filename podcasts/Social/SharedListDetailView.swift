import SwiftUI
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils

/// One shared list (Slice 7, ADR-0011). Role decides the affordances:
/// owner/collaborator edit entries (swipe-delete, drag-move — ops go straight
/// to the server, LWW), the owner manages members and metadata, everyone else
/// gets Subscribe/Unsubscribe. Entries render from server data, so lists show
/// fully even when episodes aren't in the local library; tapping an entry
/// opens the episode when it is.
struct SharedListDetailView: View {
    @EnvironmentObject var theme: Theme
    @StateObject var viewModel: SharedListDetailViewModel
    @State private var showingMembers = false
    @State private var inviteHandle = ""

    var body: some View {
        Group {
            if let page = viewModel.page {
                content(page)
            } else if viewModel.notFound {
                Text(L10n.socialProfileNotFound)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(viewModel.page?.list.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let page = viewModel.page, page.list.yourRole == .owner {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.socialListMembers) { showingMembers = true }
                }
            }
        }
        .sheet(isPresented: $showingMembers) {
            if let page = viewModel.page {
                NavigationView {
                    membersSheet(page.list)
                }
                .environmentObject(theme)
            }
        }
        .task { await viewModel.load() }
    }

    private func content(_ page: SharedListPage) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    if !page.list.description.isEmpty {
                        Text(page.list.description)
                            .font(.subheadline)
                    }
                    Text(L10n.socialListByline("@" + page.list.ownerHandle))
                        .font(.footnote)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                }
                if page.list.yourRole == .subscriber || page.list.yourRole == .none {
                    Button(page.list.yourRole == .subscriber ? L10n.socialListUnsubscribe : L10n.socialListSubscribe) {
                        Task { await viewModel.toggleSubscribe() }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }

            Section {
                ForEach(viewModel.entries) { entry in
                    Button {
                        viewModel.open(entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.episodeTitle.isEmpty ? entry.episodeUuid : entry.episodeTitle)
                                .font(.subheadline)
                                .lineLimit(2)
                            HStack(spacing: 4) {
                                if !entry.podcastTitle.isEmpty {
                                    Text(entry.podcastTitle)
                                }
                                if !entry.addedByHandle.isEmpty {
                                    Text("·")
                                    Text(L10n.socialListAddedBy("@" + entry.addedByHandle))
                                }
                            }
                            .font(.footnote)
                            .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                            .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: page.list.yourRole.canEdit ? { offsets in
                    Task { await viewModel.remove(at: offsets) }
                } : nil)
                .onMove(perform: page.list.yourRole.canEdit ? { source, destination in
                    Task { await viewModel.move(from: source, to: destination) }
                } : nil)
            }
        }
    }

    private func membersSheet(_ list: SharedList) -> some View {
        List {
            Section(footer: Text(L10n.socialListInviteFooter).font(.footnote)) {
                HStack {
                    TextField(L10n.socialHandlePlaceholder, text: $inviteHandle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(L10n.socialListInvite) {
                        let handle = inviteHandle.trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
                        inviteHandle = ""
                        guard !handle.isEmpty else { return }
                        Task { await viewModel.invite(handle: handle) }
                    }
                    .disabled(inviteHandle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section {
                ForEach(list.members) { member in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.displayName.isEmpty ? "@" + member.handle : member.displayName)
                            Text(memberRoleLabel(member.role))
                                .font(.footnote)
                                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                        }
                        Spacer()
                        Button(L10n.socialListRemoveMember) {
                            Task { await viewModel.removeMember(handle: member.handle) }
                        }
                        .font(.footnote)
                        .foregroundColor(AppTheme.color(for: .support05, theme: theme))
                    }
                }
            }
        }
        .navigationTitle(L10n.socialListMembers)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func memberRoleLabel(_ role: SharedListRole) -> String {
        switch role {
        case .collaborator: return L10n.socialListRoleCollaborator
        case .subscriber: return L10n.socialListRoleSubscriber
        default: return L10n.socialListRoleInvited
        }
    }
}

@MainActor
final class SharedListDetailViewModel: ObservableObject {
    let listId: Int64
    @Published private(set) var page: SharedListPage?
    @Published private(set) var entries: [SharedListEntry] = []
    @Published private(set) var notFound = false

    private var fixtureLoaded = false

    init(listId: Int64) {
        self.listId = listId
    }

    /// Fixture initializer for snapshots/previews; load() then no-ops.
    init(fixture: SharedListPage) {
        listId = fixture.list.id
        page = fixture
        entries = fixture.entries
        fixtureLoaded = true
    }

    func load() async {
        guard !fixtureLoaded else { return }
        guard let fetched = await ApiServerHandler.shared.fetchSharedList(id: listId) else {
            notFound = true
            return
        }
        page = fetched
        entries = fetched.entries
    }

    func toggleSubscribe() async {
        guard let page else { return }
        let subscribing = page.list.yourRole != .subscriber
        guard await ApiServerHandler.shared.subscribeToSharedList(id: listId, subscribe: subscribing) else { return }
        if subscribing {
            Analytics.track(.socialListSubscribed)
            await SocialListMirror.rebuildMirror(for: SharedList(id: listId, ownerHandle: page.list.ownerHandle,
                                                                title: page.list.title, yourRole: .subscriber))
        } else {
            SocialListMirror.removeMirror(for: listId)
        }
        fixtureLoaded = false
        await load()
    }

    /// Edits post ops directly (server LWW), then re-fetch settles the truth.
    func remove(at offsets: IndexSet) async {
        let doomed = offsets.map { entries[$0] }
        entries.remove(atOffsets: offsets)
        for entry in doomed {
            _ = await ApiServerHandler.shared.sharedListEntryOp(listId: listId, op: .remove, entry: entry)
        }
        await refetch()
    }

    func move(from source: IndexSet, to destination: Int) async {
        entries.move(fromOffsets: source, toOffset: destination)
        for (index, entry) in entries.enumerated() where entry.position != index {
            _ = await ApiServerHandler.shared.sharedListEntryOp(listId: listId, op: .move, entry: entry, position: index)
        }
        await refetch()
    }

    func invite(handle: String) async {
        _ = await ApiServerHandler.shared.inviteToSharedList(id: listId, handle: handle.lowercased())
        await refetch()
    }

    func removeMember(handle: String) async {
        _ = await ApiServerHandler.shared.removeSharedListMember(id: listId, handle: handle)
        await refetch()
    }

    func open(_ entry: SharedListEntry) {
        guard DataManager.sharedManager.findEpisode(uuid: entry.episodeUuid) != nil else { return }
        NavigationManager.sharedManager.navigateTo(NavigationManager.episodePageKey,
                                                   data: [NavigationManager.episodeUuidKey: entry.episodeUuid,
                                                          NavigationManager.podcastKey: entry.podcastUuid])
    }

    private func refetch() async {
        guard !fixtureLoaded else { return }
        if let fetched = await ApiServerHandler.shared.fetchSharedList(id: listId) {
            page = fetched
            entries = fetched.entries
        }
    }
}
