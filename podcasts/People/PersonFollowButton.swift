import PocketCastsServer
import PocketCastsUtils
import SwiftUI

/// Follow/unfollow control for a person (Highlights S12, ADR-0017). Resolves
/// the locally name-keyed person to a server identity via folded-alias search,
/// then toggles the private follow edge. Renders nothing when the flag is off,
/// the user isn't signed in, or the server doesn't know this person yet.
struct PersonFollowButton: View {
    @EnvironmentObject private var theme: Theme
    @StateObject private var model: PersonFollowModel

    init(displayName: String) {
        _model = StateObject(wrappedValue: PersonFollowModel(displayName: displayName))
    }

    var body: some View {
        if FeatureFlag.personFollows.enabled, model.state != .unavailable {
            Button {
                model.toggle()
            } label: {
                HStack(spacing: 6) {
                    if model.state == .working {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: model.state == .following ? "bell.fill" : "bell")
                    }
                    Text(model.state == .following ? L10n.personFollowingButton : L10n.personFollowButton)
                        .font(style: .footnote, weight: .semibold)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(AppTheme.color(for: model.state == .following ? .primaryUi05 : .primaryInteractive01, theme: theme)))
                .foregroundStyle(AppTheme.color(for: model.state == .following ? .primaryText01 : .primaryInteractive02, theme: theme))
            }
            .buttonStyle(.plain)
            .disabled(model.state == .working)
            .task { await model.resolve() }
        }
    }
}

@MainActor
final class PersonFollowModel: ObservableObject {
    enum State { case resolving, notFollowing, following, working, unavailable }

    @Published private(set) var state: State = .resolving
    private var serverPerson: ServerPerson?
    private let displayName: String

    init(displayName: String) {
        self.displayName = displayName
        if !SyncManager.isUserLoggedIn() {
            state = .unavailable
        }
    }

    func resolve() async {
        guard state == .resolving else { return }

        guard let matches = await ApiServerHandler.shared.searchPersons(query: displayName) else {
            state = .unavailable
            return
        }
        let folded = displayName.foldedEntityKey
        guard let match = matches.first(where: { $0.displayName.foldedEntityKey == folded }) else {
            // The search is a folded-prefix match, so a non-exact result is a
            // DIFFERENT person ("John Smit" → "John Smithers"); silently
            // following them would bind the edge to the wrong human. Until the
            // server has ingested this exact name: nothing to follow.
            state = .unavailable
            return
        }
        serverPerson = match

        let followed = await ApiServerHandler.shared.followedPersons() ?? []
        state = followed.contains(where: { $0.id == match.id }) ? .following : .notFollowing
    }

    func toggle() {
        guard let serverPerson, state == .following || state == .notFollowing else { return }
        let wasFollowing = state == .following
        state = .working

        Task { [weak self] in
            let success = wasFollowing
                ? await ApiServerHandler.shared.unfollowPerson(id: serverPerson.id)
                : await ApiServerHandler.shared.followPerson(id: serverPerson.id)
            await MainActor.run { [weak self] in
                if success {
                    self?.state = wasFollowing ? .notFollowing : .following
                    Analytics.track(wasFollowing ? .personUnfollowed : .personFollowed)
                } else {
                    self?.state = wasFollowing ? .following : .notFollowing
                }
            }
        }
    }
}
