import Foundation

/// A generic list view model that allows the user to enter a mode that allows them to select multiple items from the list and perform actions on those items
///
/// Usage:
///
///     class MyListViewModel: MultiSelectListViewModel<MyCustomModel> {
///         ...
///     }
class MultiSelectListViewModel<Model: Hashable>: ListViewModel<Model> {
    // Explicitly nonisolated: default-MainActor synthesized deinits hop executors and crash sync XCTests (swiftlang/swift#87316).
    nonisolated deinit {}
    /// Whether the list is currently in the multi selection mode
    @Published private(set) var isMultiSelecting = false

    /// The total number of items that are currently selected
    @Published private(set) var numberOfSelectedItems = 0

    /// Whether all the items in the list have been selected
    @Published private(set) var hasSelectedAll = false

    /// An internal set that keeps track of the items that are currently selected
    private(set) lazy var selectedItems: Set<Model> = [] {
        didSet {
            updateCounts()
        }
    }

    /// Update the selected items whenever the parent items change
    override var items: [Model] {
        didSet {
            validateSelectedItems()
        }
    }

    /// When multiselecting, toggle the selection state of the item
    /// If not, then do nothing.
    func tapped(item: Model) {
        guard isMultiSelecting else { return }

        toggleSelected(item)
    }

    // MARK: - Entering / Exiting Multi Select

    func toggleMultiSelection() {
        deselectAll()
        isMultiSelecting.toggle()
    }

    // MARK: - Item Selection

    func isSelected(_ item: Model) -> Bool {
        selectedItems.contains(where: { $0 == item })
    }

    func select(item: Model) {
        selectedItems.insert(item)
    }

    func deselect(item: Model) {
        selectedItems.remove(item)
    }

    func toggleSelected(_ item: Model) {
        isSelected(item) ? deselect(item: item) : select(item: item)
    }

    // MARK: - Select All / Deselect All

    /// The items bulk-selection operates on. Subclasses whose rendered list is
    /// narrowed (search, tag filter) override this so Select All can never
    /// select — and a later Delete never destroys — rows the user can't see.
    var selectableItems: [Model] { items }

    /// Call whenever the rendered list narrows without `items` changing
    /// (search results shifting mid-multi-select): rows that fell out of view
    /// must not stay selected, or a later Delete destroys rows the user
    /// can't see. Always refreshes the counts and Select All state.
    func selectableItemsChanged() {
        selectedItems.formIntersection(selectableItems)
    }

    func toggleSelectAll() {
        hasSelectedAll ? deselectAll() : selectAll()
    }

    func selectAll() {
        selectedItems = Set(selectableItems)
    }

    func deselectAll() {
        selectedItems.removeAll()
    }

    // MARK: - Select All Before/After

    func selectAllBefore(_ item: Model) {
        let selectable = selectableItems
        guard let index = selectable.firstIndex(of: item) else { return }

        selectedItems.formUnion(selectable[...index])
    }

    func selectAllAfter(_ item: Model) {
        let selectable = selectableItems
        guard let index = selectable.firstIndex(of: item) else { return }

        selectedItems.formUnion(selectable[index...])
    }

    // MARK: - Long Press

    /// Handles when an item is long pressed:
    /// - If we're not currently in the multi selection mode, then we'll enter and select the pressed item
    /// - Otherwise we'll show the Select All Above/Below options picker
    func longPressed(_ item: Model) {
        // If we're not multiselecting, then enter and select the long pressed item
        guard isMultiSelecting else {
            isMultiSelecting = true
            select(item: item)
            return
        }

        // Show the select all above/below options
        showOptionsPicker(item)
    }

    // MARK: - Options Picker

    /// Shows the default option picker to allow for Select All Above/Below
    func showOptionsPicker(_ item: Model) {
        let optionPicker = OptionsPicker(title: nil)

        optionPicker.addActions([
            .init(label: L10n.selectAllAbove, icon: "selectall-up") { [weak self] in
                self?.selectAllBefore(item)
            },
            .init(label: L10n.selectAllBelow, icon: "selectall-down") { [weak self] in
                self?.selectAllAfter(item)
            }
        ])

        optionPicker.show(statusBarStyle: AppTheme.defaultStatusBarStyle())
    }
}

// MARK: - Private Methods

private extension MultiSelectListViewModel {
    func updateCounts() {
        numberOfSelectedItems = selectedItems.count
        // Set containment, not count equality: counts alias when hidden rows
        // are selected, and an empty list has never "selected all".
        let selectable = Set(selectableItems)
        hasSelectedAll = !selectable.isEmpty && selectedItems.isSuperset(of: selectable)
    }

    func validateSelectedItems() {
        // Update the selected items to remove any items that are not present in the items array
        // IE: if they were deleted
        selectedItems.formIntersection(items)

        // If we're multiselecting and there are no items left, exit the multiselection mode
        if isMultiSelecting, numberOfItems == 0 {
            toggleMultiSelection()
        }
    }
}
