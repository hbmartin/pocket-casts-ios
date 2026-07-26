import Foundation
import PocketCastsUtils
import UIKit

/// Shared helpers for screens backed by UIKit diffable data sources.
nonisolated enum DiffableHelpers {
    /// Builds a snapshot from ordered (section, items) pairs.
    ///
    /// Duplicate identifiers are a hard crash inside `apply(_:)`, so duplicate
    /// items are dropped (first occurrence wins) and duplicate sections have
    /// their items merged into the first occurrence, with a log for either.
    static func snapshot<Section: Hashable & Sendable, Item: Hashable & Sendable>(
        sections: [(section: Section, items: [Item])]
    ) -> NSDiffableDataSourceSnapshot<Section, Item> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        var seenItems = Set<Item>()
        var seenSections = Set<Section>()
        for entry in sections {
            if seenSections.insert(entry.section).inserted {
                snapshot.appendSections([entry.section])
            } else {
                FileLog.shared.addMessage("DiffableHelpers: merged duplicate section \(entry.section)")
            }
            let uniqueItems = entry.items.filter { item in
                let inserted = seenItems.insert(item).inserted
                if !inserted {
                    FileLog.shared.addMessage("DiffableHelpers: dropped duplicate item identifier \(item)")
                }
                return inserted
            }
            snapshot.appendItems(uniqueItems, toSection: entry.section)
        }
        return snapshot
    }

    /// Identifiers present in both fingerprint maps whose fingerprints differ —
    /// the set to pass to `reconfigureItems(_:)` so their cells re-render in
    /// place instead of being deleted and reinserted.
    static func changedIDs<Item: Hashable>(old: [Item: Int], new: [Item: Int]) -> [Item] {
        new.compactMap { id, fingerprint in
            guard let oldFingerprint = old[id], oldFingerprint != fingerprint else { return nil }
            return id
        }
    }
}
