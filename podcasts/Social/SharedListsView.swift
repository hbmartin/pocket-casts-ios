import SwiftUI
import PocketCastsServer
import PocketCastsUtils

/// The shared-lists hub (Slice 7, ADR-0011): everything the account owns,
/// collaborates on, or subscribes to, plus pending collaboration invites.
/// Reached from the Profile tab.
struct SharedListsView: View {
    @EnvironmentObject var theme: Theme
    @StateObject var viewModel: SharedListsViewModel

    var body: some View {
        List {
            if !viewModel.invites.isEmpty {
                Section(header: Text(L10n.socialListInvitesTitle)) {
                    ForEach(viewModel.invites) { invite in
                        inviteRow(invite)
                    }
                }
            }

            if viewModel.lists.isEmpty, !viewModel.isLoading {
                Section {
                    Text(L10n.socialListsEmpty)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                }
            } else {
                ForEach(viewModel.lists) { list in
                    NavigationLink(destination: SharedListDetailView(viewModel: SharedListDetailViewModel(listId: list.id))
                        .environmentObject(theme)) {
                        listRow(list)
                    }
                }
            }
        }
        .navigationTitle(L10n.socialListsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    private func listRow(_ list: SharedList) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(list.title)
                .font(.subheadline.weight(.medium))
            HStack(spacing: 4) {
                Text(roleLabel(list.yourRole))
                Text("·")
                Text("@" + list.ownerHandle)
                Text("·")
                Text(list.entryCount == 1 ? L10n.socialListEpisodeCountSingular : L10n.socialListEpisodeCount(list.entryCount))
            }
            .font(.footnote)
            .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        }
        .padding(.vertical, 2)
    }

    private func inviteRow(_ invite: SharedList) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(invite.title)
                    .font(.subheadline.weight(.medium))
                Text(L10n.socialListInviteFrom("@" + invite.ownerHandle))
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

    private func roleLabel(_ role: SharedListRole) -> String {
        switch role {
        case .owner: return L10n.socialListRoleOwner
        case .collaborator: return L10n.socialListRoleCollaborator
        default: return L10n.socialListRoleSubscriber
        }
    }
}

@MainActor
final class SharedListsViewModel: ObservableObject {
    typealias FetchLists = @MainActor () async -> SharedListsOverview?
    typealias RespondToInvite = @MainActor (_ id: Int64, _ accept: Bool) async -> Bool
    typealias RefreshMirrors = @MainActor () async -> SharedListsOverview?

    @Published private(set) var lists: [SharedList] = []
    @Published private(set) var invites: [SharedList] = []
    @Published private(set) var isLoading = true

    private var fixtureLoaded = false
    private let fetchLists: FetchLists
    private let respondToInvite: RespondToInvite
    private let refreshMirrors: RefreshMirrors

    init(
        fetchLists: @escaping FetchLists = { await ApiServerHandler.shared.fetchSharedLists() },
        respondToInvite: @escaping RespondToInvite = { id, accept in
            await ApiServerHandler.shared.respondToSharedListInvite(id: id, accept: accept)
        },
        refreshMirrors: @escaping RefreshMirrors = { await SocialListMirror.refreshAll() }
    ) {
        self.fetchLists = fetchLists
        self.respondToInvite = respondToInvite
        self.refreshMirrors = refreshMirrors
    }

    /// Fixture initializer for snapshots/previews; load() then no-ops.
    init(
        fixture: [SharedList],
        invites: [SharedList] = [],
        fetchLists: @escaping FetchLists = { await ApiServerHandler.shared.fetchSharedLists() },
        respondToInvite: @escaping RespondToInvite = { id, accept in
            await ApiServerHandler.shared.respondToSharedListInvite(id: id, accept: accept)
        },
        refreshMirrors: @escaping RefreshMirrors = { await SocialListMirror.refreshAll() }
    ) {
        self.fetchLists = fetchLists
        self.respondToInvite = respondToInvite
        self.refreshMirrors = refreshMirrors
        lists = fixture
        self.invites = invites
        isLoading = false
        fixtureLoaded = true
    }

    func load() async {
        guard !fixtureLoaded else { return }
        Analytics.track(.socialListsShown)
        if let overview = await fetchLists() {
            lists = overview.lists
            invites = overview.invites
        }
        isLoading = false
    }

    func respond(to invite: SharedList, accept: Bool) async {
        guard await respondToInvite(invite.id, accept) else { return }

        let overview: SharedListsOverview?
        if accept {
            Analytics.track(.socialListInviteAccepted)
            overview = await refreshMirrors()
        } else {
            overview = await fetchLists()
        }

        if let overview {
            lists = overview.lists
            invites = overview.invites
        } else {
            invites.removeAll { $0.id == invite.id }
        }
    }
}
