import Foundation
import PocketCastsDataModel

/// Groups uploaded files by their sync subfolder for the Files screen.
///
/// The root group (empty name) always comes first and is always present — even
/// with no root uploads, or no uploads at all — because the Files table hangs
/// its storage header off the root section. Named groups follow A-Z. The
/// caller's episode order is preserved inside each group.
nonisolated enum UploadedGroupsBuilder {
    static func groups(from episodes: [UserEpisode]) -> [(group: String, episodes: [UserEpisode])] {
        let grouped = Dictionary(grouping: episodes) { $0.groupName ?? "" }
        let sections = grouped
            .sorted { lhs, rhs in
                if lhs.key.isEmpty != rhs.key.isEmpty { return lhs.key.isEmpty }
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
            .map { (group: $0.key, episodes: $0.value) }
        guard sections.first?.group.isEmpty == true else {
            return [(group: "", episodes: [])] + sections
        }
        return sections
    }
}
