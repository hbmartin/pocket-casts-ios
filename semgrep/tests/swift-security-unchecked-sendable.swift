import Foundation

// ruleid: pocketcasts.unchecked-sendable-requires-justification
final class UnjustifiedBox: @unchecked Sendable {
    let value: Int = 0
}

private let boxLock = NSLock()

// ok: pocketcasts.unchecked-sendable-requires-justification
// @unchecked Sendable: all mutable state is guarded by boxLock.
final class JustifiedByPrecedingComment: @unchecked Sendable {
    var value: Int = 0
}

// ok: pocketcasts.unchecked-sendable-requires-justification
/// @unchecked Sendable because the wrapped formatter is never mutated after init.
final class JustifiedByDocComment: @unchecked Sendable {
    let formatter = DateFormatter()
}

// ok: pocketcasts.unchecked-sendable-requires-justification
final class JustifiedInline: @unchecked Sendable {} // @unchecked Sendable: stateless marker type.

// A comment that merely repeats the keyword with no reason justifies nothing.
// @unchecked Sendable
// ruleid: pocketcasts.unchecked-sendable-requires-justification
final class BareKeywordNoReason: @unchecked Sendable {
    var value: Int = 0
}

// A comment that does not reference the keyword is not greppable as a justification.
// All access guarded by boxLock.
// ruleid: pocketcasts.unchecked-sendable-requires-justification
final class CommentWithoutKeyword: @unchecked Sendable {
    var value: Int = 0
}

// @unchecked Sendable: this explanation belongs to the next declaration only.
// An unrelated comment breaks adjacency.
// ruleid: pocketcasts.unchecked-sendable-requires-justification
final class StaleInterveningJustification: @unchecked Sendable {
    var value: Int = 0
}

// Extension-based retroactive conformance is covered by the same token.
// ruleid: pocketcasts.unchecked-sendable-requires-justification
extension UnjustifiedBox2: @unchecked Sendable {}

final class UnjustifiedBox2 {
    var value: Int = 0
}
