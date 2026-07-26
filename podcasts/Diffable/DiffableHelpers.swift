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

    /// Replaces selected value-type models with their latest fetched values
    /// and drops identifiers that are no longer present.
    static func refreshedSelection<Model, ID: Hashable>(
        _ selectedModels: [Model],
        id: (Model) -> ID,
        modelsByID: [ID: Model]
    ) -> [Model] {
        selectedModels.compactMap { modelsByID[id($0)] }
    }

    /// Applies a table snapshot and guarantees that `completion` runs after
    /// either the animated update or its reload-data fallback has finished.
    @MainActor
    static func apply<Section: Hashable & Sendable, Item: Hashable & Sendable>(
        _ snapshot: NSDiffableDataSourceSnapshot<Section, Item>,
        to dataSource: UITableViewDiffableDataSource<Section, Item>,
        animatingDifferences: Bool,
        context: String,
        completion: (() -> Void)? = nil
    ) {
        performApply(
            animatingDifferences: animatingDifferences,
            context: context,
            animatedApply: {
                dataSource.apply(snapshot, animatingDifferences: true, completion: completion)
            },
            reloadApply: {
                dataSource.applySnapshotUsingReloadData(snapshot, completion: completion)
            }
        )
    }

    /// Collection-view counterpart to the table helper above.
    @MainActor
    static func apply<Section: Hashable & Sendable, Item: Hashable & Sendable>(
        _ snapshot: NSDiffableDataSourceSnapshot<Section, Item>,
        to dataSource: UICollectionViewDiffableDataSource<Section, Item>,
        animatingDifferences: Bool,
        context: String,
        completion: (() -> Void)? = nil
    ) {
        performApply(
            animatingDifferences: animatingDifferences,
            context: context,
            animatedApply: {
                dataSource.apply(snapshot, animatingDifferences: true, completion: completion)
            },
            reloadApply: {
                dataSource.applySnapshotUsingReloadData(snapshot, completion: completion)
            }
        )
    }

    @MainActor
    private static func performApply(
        animatingDifferences: Bool,
        context: String,
        animatedApply: () -> Void,
        reloadApply: () -> Void
    ) {
        guard animatingDifferences else {
            reloadApply()
            return
        }

        do {
            // UIKit can raise an Objective-C exception if its state is
            // mid-flight (for example, while SwipeCellKit has a row open).
            try SJCommonUtils.catchException(animatedApply)
        } catch {
            FileLog.shared.addMessage("\(context): diffable apply failed, falling back to reload: \(error)")
            reloadApply()
        }
    }
}

/// Main-actor-owned generation gate for cancel-and-replace refresh pipelines.
/// Operation cancellation is cooperative, so controllers also compare the
/// captured generation immediately before mutating their UI.
@MainActor
struct LatestRefreshGate {
    private var generation = 0

    mutating func begin() -> Int {
        generation &+= 1
        return generation
    }

    mutating func invalidate() {
        generation &+= 1
    }

    func isCurrent(_ candidate: Int) -> Bool {
        candidate == generation
    }
}
