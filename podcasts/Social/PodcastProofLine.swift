import SwiftUI
import PocketCastsServer
import PocketCastsUtils

/// The podcast-page social-proof line (Slice 10, docs/Social.md): "Followed
/// by @a, @b and N more you follow" — named only when each person's
/// followed-shows visibility already grants this account their list; the rest
/// fold into the count. Renders nothing for non-joined accounts or when no
/// followee follows the show.
struct PodcastProofLine: View {
    @EnvironmentObject var theme: Theme
    let podcastUuid: String
    @State private var proof: PodcastProof?

    /// Fixture support for snapshots: a preset proof skips the fetch.
    init(podcastUuid: String, fixture: PodcastProof? = nil) {
        self.podcastUuid = podcastUuid
        _proof = State(initialValue: fixture)
    }

    var body: some View {
        Group {
            if let proof, proof.totalCount > 0 {
                Text(proofText(proof))
                    .font(.footnote)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                    .multilineTextAlignment(.center)
            }
        }
        .task {
            guard proof == nil, SocialIdentityStore.isJoined else { return }
            proof = await ApiServerHandler.shared.fetchPodcastProof(podcastUuid: podcastUuid)
        }
    }

    private func proofText(_ proof: PodcastProof) -> String {
        let names = proof.visibleHandles.map { "@" + $0 }.joined(separator: ", ")
        let remainder = proof.totalCount - proof.visibleHandles.count
        if names.isEmpty {
            return L10n.socialProofCountOnly(proof.totalCount)
        }
        if remainder > 0 {
            return L10n.socialProofNamedAndMore(names, remainder)
        }
        return L10n.socialProofNamed(names)
    }
}
