import Foundation

/// The versioned envelope persisted in `EpisodeFilter.customQuery` (as JSON).
///
/// Two modes:
/// - `builder`: a `CustomQueryNode` AST, recompiled at query time (never store the
///   compiled SQL) so relative dates evaluate freshly, matching the smart-playlist
///   `filterTimeFor(hours:)` semantics.
/// - `sql`: a raw SQL WHERE-clause body over the `episode`/`podcast` table aliases,
///   accepted only after passing `PlaylistQueryValidator` at save time.
///
/// Robustness contract: anything unreadable — missing JSON, undecodable JSON, an
/// unknown mode, or a version newer than `currentVersion` — must compile to the
/// always-empty rule fragment (`(0)`), never crash. See
/// `PlaylistQueryBuilder.customRuleFragment(for:)`.
public struct CustomPlaylistQuery: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case builder
        case sql
    }

    /// The newest envelope version this build can interpret.
    public static let currentVersion = 1

    public var version: Int
    public var mode: Mode
    /// Builder mode: the AST root. Ignored in `sql` mode.
    public var root: CustomQueryNode?
    /// SQL mode: the validated WHERE-clause body. Ignored in `builder` mode.
    public var sql: String?

    public init(root: CustomQueryNode) {
        self.version = Self.currentVersion
        self.mode = .builder
        self.root = root
        self.sql = nil
    }

    public init(sql: String) {
        self.version = Self.currentVersion
        self.mode = .sql
        self.root = nil
        self.sql = sql
    }

    /// Decodes an envelope from the persisted JSON string.
    /// Returns nil when the JSON is missing or undecodable; callers treat that as the
    /// unsupported-query state (renders empty).
    public init?(envelopeJSON: String?) {
        guard let envelopeJSON,
              let data = envelopeJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(CustomPlaylistQuery.self, from: data) else {
            return nil
        }
        self = decoded
    }

    /// Whether this build knows how to compile the envelope. Envelopes written by a
    /// future version render empty instead of guessing.
    public var isSupported: Bool {
        version >= 1 && version <= Self.currentVersion
    }

    /// Serializes the envelope for persistence in `EpisodeFilter.customQuery`.
    public func envelopeJSON() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard let json = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(self, EncodingError.Context(codingPath: [], debugDescription: "Envelope did not produce UTF-8"))
        }
        return json
    }
}
