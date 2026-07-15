import Foundation

/// The builder-mode AST: nested All/Any groups over typed conditions.
///
/// Encoded with a `type` discriminator:
/// ```json
/// { "type": "group", "op": "all", "children": [ ... ] }
/// { "type": "condition", "field": "duration", "op": "greaterThan", "value": { "number": 1800 } }
/// ```
/// Unknown discriminators, fields or operators fail decoding, which the envelope
/// loader (`CustomPlaylistQuery.init(envelopeJSON:)`) maps to the render-empty state.
///
/// Size caps (depth <= `CustomQueryCompiler.maxDepth`, children per group <=
/// `maxChildrenPerGroup`, total conditions <= `maxConditions`) are enforced by the
/// compiler, which throws instead of producing oversized SQL.
public indirect enum CustomQueryNode: Codable, Equatable, Sendable {
    case group(CustomQueryGroup)
    case condition(CustomQueryCondition)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum NodeType: String, Codable {
        case group
        case condition
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(NodeType.self, forKey: .type) {
        case .group:
            self = .group(try CustomQueryGroup(from: decoder))
        case .condition:
            self = .condition(try CustomQueryCondition(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .group(let group):
            try container.encode(NodeType.group, forKey: .type)
            try group.encode(to: encoder)
        case .condition(let condition):
            try container.encode(NodeType.condition, forKey: .type)
            try condition.encode(to: encoder)
        }
    }
}

public extension CustomQueryNode {
    /// True when any condition in the tree reads `field` (used for analytics on
    /// playlist save; not a compile-path concern).
    func contains(field: CustomQueryField) -> Bool {
        switch self {
        case .condition(let condition):
            condition.field == field
        case .group(let group):
            group.children.contains { $0.contains(field: field) }
        }
    }
}

/// A boolean combinator over child nodes: `all` = AND, `any` = OR.
public struct CustomQueryGroup: Codable, Equatable, Sendable {
    public enum Operator: String, Codable, Sendable {
        case all
        case any
    }

    public var op: Operator
    public var children: [CustomQueryNode]

    public init(op: Operator, children: [CustomQueryNode]) {
        self.op = op
        self.children = children
    }

    private enum CodingKeys: String, CodingKey {
        case op
        case children
    }
}

/// A single field comparison. `value` carries the primary operand; `secondValue`
/// is only used by `between` (the inclusive upper bound).
public struct CustomQueryCondition: Codable, Equatable, Sendable {
    public var field: CustomQueryField
    public var op: CustomQueryOperator
    public var value: CustomQueryValue?
    public var secondValue: CustomQueryValue?

    public init(field: CustomQueryField, op: CustomQueryOperator, value: CustomQueryValue? = nil, secondValue: CustomQueryValue? = nil) {
        self.field = field
        self.op = op
        self.value = value
        self.secondValue = secondValue
    }

    private enum CodingKeys: String, CodingKey {
        case field
        case op
        case value
        case secondValue
    }
}

/// A typed operand, encoded as a single-key object so the JSON stays
/// self-describing: `{"string": "x"}`, `{"number": 42}`, `{"bool": true}`,
/// `{"epoch": 1731542400}`, `{"relativeDays": 7}`, `{"stringList": ["a","b"]}`.
public enum CustomQueryValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case date(CustomQueryDateValue)
    case stringList([String])

    private enum CodingKeys: String, CodingKey {
        case string
        case number
        case bool
        case epoch
        case relativeDays
        case stringList
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let string = try container.decodeIfPresent(String.self, forKey: .string) {
            self = .string(string)
        } else if let number = try container.decodeIfPresent(Double.self, forKey: .number) {
            self = .number(number)
        } else if let bool = try container.decodeIfPresent(Bool.self, forKey: .bool) {
            self = .bool(bool)
        } else if let epoch = try container.decodeIfPresent(TimeInterval.self, forKey: .epoch) {
            self = .date(.epoch(epoch))
        } else if let days = try container.decodeIfPresent(Int.self, forKey: .relativeDays) {
            self = .date(.relativeDays(days))
        } else if let list = try container.decodeIfPresent([String].self, forKey: .stringList) {
            self = .stringList(list)
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "CustomQueryValue requires exactly one of: string, number, bool, epoch, relativeDays, stringList"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let string):
            try container.encode(string, forKey: .string)
        case .number(let number):
            try container.encode(number, forKey: .number)
        case .bool(let bool):
            try container.encode(bool, forKey: .bool)
        case .date(.epoch(let epoch)):
            try container.encode(epoch, forKey: .epoch)
        case .date(.relativeDays(let days)):
            try container.encode(days, forKey: .relativeDays)
        case .stringList(let list):
            try container.encode(list, forKey: .stringList)
        }
    }
}

/// A date operand: an absolute `timeIntervalSince1970`, or a day offset resolved
/// against `now` at every compile so builder playlists stay fresh.
public enum CustomQueryDateValue: Equatable, Sendable {
    case epoch(TimeInterval)
    case relativeDays(Int)

    /// The absolute timestamp this value denotes when compiled at `now`.
    public func resolved(now: Date) -> TimeInterval {
        switch self {
        case .epoch(let epoch):
            return epoch
        case .relativeDays(let days):
            return now.addingTimeInterval(-TimeInterval(days) * 24 * 3600).timeIntervalSince1970
        }
    }
}
