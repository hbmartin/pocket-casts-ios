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
    @Published private(set) var lists: [SharedList] = []
    @Published private(set) var invites: [SharedList] = []
    @Published private(set) var isLoading = true

    private var fixtureLoaded = false

    init() {}

    /// Fixture initializer for snapshots/previews; load() then no-ops.
    init(fixture: [SharedList], invites: [SharedList] = []) {
        lists = fixture
        self.invites = invites
        isLoading = false
        fixtureLoaded = true
    }

    func load() async {
        guard !fixtureLoaded else { return }
        Analytics.track(.socialListsShown)
        if let overview = await ApiServerHandler.shared.fetchSharedLists() {
            lists = overview.lists
            invites = overview.invites
        }
        isLoading = false
    }

    func respond(to invite: SharedList, accept: Bool) async {
        guard await ApiServerHandler.shared.respondToSharedListInvite(id: invite.id, accept: accept) else { return }
        if accept {
            Analytics.track(.socialListInviteAccepted)
            await SocialListMirror.refreshAll()
        }
        invites.removeAll { $0.id == invite.id }
        if let overview = await ApiServerHandler.shared.fetchSharedLists() {
            lists = overview.lists
        }
    }
}
