import Foundation
import PocketCastsDataModel

/// UI aliases for the engine compiler's enforced limits, so builder affordances
/// disable at exactly the caps the compiler would reject.
nonisolated enum CustomQueryLimits {
    /// Maximum group nesting depth; the root group is depth 1.
    static let maxDepth = CustomQueryCompiler.maxDepth
    /// Maximum direct children (conditions + groups) per group.
    static let maxChildrenPerGroup = CustomQueryCompiler.maxChildrenPerGroup
    /// Maximum conditions across the whole document.
    static let maxConditions = CustomQueryCompiler.maxConditions
}

/// Editable value slots for a condition row. Which slots are read depends on the
/// field kind and operator; unused slots keep their defaults.
nonisolated struct CustomQueryDraftValue: Equatable {
    var text: String = ""
    var numberText: String = ""
    var secondNumberText: String = ""
    var boolValue: Bool = true
    var date: Date = Calendar.current.startOfDay(for: Date())
    var secondDate: Date = Calendar.current.startOfDay(for: Date())
    var daysText: String = "7"
    /// Enumeration identifiers or podcast uuids for in/notIn operators.
    var selectedValues: [String] = []
}

nonisolated struct CustomQueryDraftCondition: Identifiable, Equatable {
    let id: UUID
    var field: CustomQueryField
    var op: CustomQueryOperator
    var value: CustomQueryDraftValue

    static func makeDefault(for field: CustomQueryField) -> CustomQueryDraftCondition {
        CustomQueryDraftCondition(
            id: UUID(),
            field: field,
            op: field.allowedOperators.first ?? .equals,
            value: CustomQueryDraftValue()
        )
    }

    /// Switching fields resets the operator and value: stale values from another
    /// field kind must never leak into the compiled query.
    func changingField(to newField: CustomQueryField) -> CustomQueryDraftCondition {
        CustomQueryDraftCondition(
            id: id,
            field: newField,
            op: newField.allowedOperators.first ?? .equals,
            value: CustomQueryDraftValue()
        )
    }

    func changingOperator(to newOp: CustomQueryOperator) -> CustomQueryDraftCondition {
        var copy = self
        copy.op = newOp
        return copy
    }

    /// Whether the row has everything the compiler needs.
    var isComplete: Bool {
        guard field.allowedOperators.contains(op) else { return false }

        switch field.kind {
        case .text:
            return !value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .number:
            switch op {
            case .isSet, .isNotSet:
                return true
            case .between:
                return Double(value.numberText) != nil && Double(value.secondNumberText) != nil
            default:
                return Double(value.numberText) != nil
            }
        case .boolean:
            return true
        case .date:
            switch op {
            case .isSet, .isNotSet, .before, .after:
                return true
            case .between:
                return value.date <= value.secondDate
            case .inLastDays:
                guard let days = Int(value.daysText) else { return false }
                return days > 0
            default:
                return false
            }
        case .enumeration, .podcastList:
            return !value.selectedValues.isEmpty
        }
    }
}

nonisolated struct CustomQueryDraftGroup: Identifiable, Equatable {
    enum Match: String, CaseIterable, Equatable {
        case all
        case any
    }

    let id: UUID
    var match: Match
    var children: [CustomQueryDraftNode]

    init(id: UUID = UUID(), match: Match = .all, children: [CustomQueryDraftNode] = []) {
        self.id = id
        self.match = match
        self.children = children
    }
}

nonisolated enum CustomQueryDraftNode: Identifiable, Equatable {
    case group(CustomQueryDraftGroup)
    case condition(CustomQueryDraftCondition)

    var id: UUID {
        switch self {
        case .group(let group): group.id
        case .condition(let condition): condition.id
        }
    }
}

// MARK: - Document queries

nonisolated extension CustomQueryDraftGroup {
    var totalConditionCount: Int {
        children.reduce(0) { count, child in
            switch child {
            case .condition:
                count + 1
            case .group(let group):
                count + group.totalConditionCount
            }
        }
    }

    var allConditionsComplete: Bool {
        children.allSatisfy { child in
            switch child {
            case .condition(let condition):
                condition.isComplete
            case .group(let group):
                group.allConditionsComplete
            }
        }
    }

    /// Depth of the group with `groupID`, where the receiver is at `currentDepth` (root = 1).
    func depth(ofGroupID groupID: UUID, currentDepth: Int = 1) -> Int? {
        if id == groupID { return currentDepth }
        for child in children {
            if case .group(let group) = child,
               let depth = group.depth(ofGroupID: groupID, currentDepth: currentDepth + 1) {
                return depth
            }
        }
        return nil
    }

    func group(withID groupID: UUID) -> CustomQueryDraftGroup? {
        if id == groupID { return self }
        for child in children {
            if case .group(let group) = child, let found = group.group(withID: groupID) {
                return found
            }
        }
        return nil
    }

    func condition(withID conditionID: UUID) -> CustomQueryDraftCondition? {
        for child in children {
            switch child {
            case .condition(let condition) where condition.id == conditionID:
                return condition
            case .group(let group):
                if let found = group.condition(withID: conditionID) { return found }
            default:
                break
            }
        }
        return nil
    }
}

// MARK: - Document edits

nonisolated extension CustomQueryDraftGroup {
    /// Appends `node` to the group with `groupID`. Returns false when the target
    /// group doesn't exist. Cap checks live in the view model so failures can
    /// drive UI state; this is pure tree surgery.
    @discardableResult
    mutating func append(_ node: CustomQueryDraftNode, toGroupID groupID: UUID) -> Bool {
        if id == groupID {
            children.append(node)
            return true
        }
        for index in children.indices {
            if case .group(var group) = children[index] {
                if group.append(node, toGroupID: groupID) {
                    children[index] = .group(group)
                    return true
                }
            }
        }
        return false
    }

    /// Removes the node (condition or nested group) with `nodeID`. The root
    /// group itself can't be removed.
    @discardableResult
    mutating func removeNode(id nodeID: UUID) -> Bool {
        if let index = children.firstIndex(where: { $0.id == nodeID }) {
            children.remove(at: index)
            return true
        }
        for index in children.indices {
            if case .group(var group) = children[index] {
                if group.removeNode(id: nodeID) {
                    children[index] = .group(group)
                    return true
                }
            }
        }
        return false
    }

    @discardableResult
    mutating func updateCondition(_ condition: CustomQueryDraftCondition) -> Bool {
        for index in children.indices {
            switch children[index] {
            case .condition(let existing) where existing.id == condition.id:
                children[index] = .condition(condition)
                return true
            case .group(var group):
                if group.updateCondition(condition) {
                    children[index] = .group(group)
                    return true
                }
            default:
                break
            }
        }
        return false
    }

    @discardableResult
    mutating func setMatch(_ newMatch: Match, forGroupID groupID: UUID) -> Bool {
        if id == groupID {
            match = newMatch
            return true
        }
        for index in children.indices {
            if case .group(var group) = children[index] {
                if group.setMatch(newMatch, forGroupID: groupID) {
                    children[index] = .group(group)
                    return true
                }
            }
        }
        return false
    }
}
