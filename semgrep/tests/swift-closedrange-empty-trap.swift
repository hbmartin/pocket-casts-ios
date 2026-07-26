import UIKit

// Fixture for pocketcasts.closedrange-upper-bound-minus-one: `low ... high - 1`
// traps when high is 0 (empty collection / zero-row section). The half-open
// `low ..< high` is empty-safe and otherwise equivalent.

func closedRangeTraps(items: [String], table: UITableView, section: Int) {
    // ruleid: pocketcasts.closedrange-upper-bound-minus-one
    for index in 0 ... items.count - 1 {
        _ = items[index]
    }

    // ruleid: pocketcasts.closedrange-upper-bound-minus-one
    let range = 0 ... (items.count - 1)
    _ = range

    // ruleid: pocketcasts.closedrange-upper-bound-minus-one
    let rows = 0 ... table.numberOfRows(inSection: section) - 1
    _ = rows
}

func safeAlternatives(items: [String], startingRow: Int) {
    // ok: pocketcasts.closedrange-upper-bound-minus-one
    for index in 0 ..< items.count {
        _ = items[index]
    }

    // ok: pocketcasts.closedrange-upper-bound-minus-one
    let clamped = 0 ... max(items.count - 1, 0)
    _ = clamped

    // ok: pocketcasts.closedrange-upper-bound-minus-one
    let bounded = startingRow ... min(4, items.count - 1)
    _ = bounded
}
