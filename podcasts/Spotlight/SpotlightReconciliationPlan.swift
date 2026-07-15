import Foundation

/// Pure diff between what Spotlight should contain and what this app last wrote
/// to it. Everything expected is re-indexed (refreshing attributes and
/// expiration dates); only identifiers this app previously wrote and no longer
/// expects are deleted — reconciliation never touches other domains.
nonisolated enum SpotlightReconciliationPlan {
    struct Plan: Equatable, Sendable {
        let toDelete: [String]
        let toIndex: [String]
    }

    static func make(expected: Set<String>, persisted: Set<String>) -> Plan {
        Plan(
            toDelete: persisted.subtracting(expected).sorted(),
            toIndex: expected.sorted()
        )
    }
}
