import SwiftUI
import PocketCastsServer

/// The podcast page's fandom-hub line (Slice 14 debt from ADR-0012): shows
/// how many public groups anchor to this show, opens the list, and offers
/// "Start a group" pre-anchored. Anchors are non-exclusive by design.
struct PodcastHubsLine: View {
    @EnvironmentObject var theme: Theme
    let podcastUuid: String
    let podcastTitle: String

    @State private var hubs: [SocialGroup] = []
    @State private var loaded = false
    @State private var showingHubs = false

    var body: some View {
        Group {
            if loaded {
                Button {
                    showingHubs = true
                } label: {
                    Label(hubs.isEmpty
                        ? L10n.socialHubsStart
                        : (hubs.count == 1 ? L10n.socialHubsCountSingular : L10n.socialHubsCount(hubs.count)),
                        systemImage: "person.3")
                        .font(.footnote.bold())
                        .foregroundColor(AppTheme.color(for: .primaryInteractive01, theme: theme))
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showingHubs) {
                    NavigationView {
                        PodcastHubsListView(podcastUuid: podcastUuid, podcastTitle: podcastTitle, hubs: hubs)
                    }
                    .navigationViewStyle(.stack)
                    .environmentObject(theme)
                }
            }
        }
        .task {
            guard !loaded, SocialIdentityStore.isJoined else { return }
            hubs = await ApiServerHandler.shared.groupsForPodcast(uuid: podcastUuid)
            loaded = true
        }
    }
}

/// The sheet listing a show's hubs, plus the pre-anchored create entry.
struct PodcastHubsListView: View {
    @EnvironmentObject var theme: Theme
    let podcastUuid: String
    let podcastTitle: String
    @State var hubs: [SocialGroup]
    @State private var showingCreate = false

    var body: some View {
        List {
            if hubs.isEmpty {
                Text(L10n.socialHubsEmpty)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            } else {
                ForEach(hubs) { hub in
                    NavigationLink(destination: GroupDetailView(viewModel: GroupDetailViewModel(groupId: hub.id))
                        .environmentObject(theme)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hub.title)
                                .font(.subheadline.weight(.medium))
                            Text(hub.memberCount == 1 ? L10n.socialGroupMemberCountSingular : L10n.socialGroupMemberCount(hub.memberCount))
                                .font(.footnote)
                                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                        }
                    }
                }
            }
            Button {
                showingCreate = true
            } label: {
                Label(L10n.socialHubsStart, systemImage: "plus")
            }
        }
        .navigationTitle(L10n.socialGroupsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCreate) {
            NavigationView {
                CreateGroupView(onDone: { group in
                    showingCreate = false
                    if let group {
                        hubs.insert(group, at: 0)
                    }
                }, anchorUuid: podcastUuid, anchorTitle: podcastTitle, startPublic: true)
                .environmentObject(theme)
            }
        }
    }
}
