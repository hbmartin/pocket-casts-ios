import Foundation

// ruleid: pocketcasts.unchecked-sendable-requires-justification
final class UnjustifiedBox: @unchecked Sendable {
    let value: Int = 0
}

private let boxLock = NSLock()

// @unchecked Sendable: all mutable state is guarded by boxLock.
// ok: pocketcasts.unchecked-sendable-requires-justification
final class JustifiedByPrecedingComment: @unchecked Sendable {
    var value: Int = 0
}

/// Conforms via @unchecked Sendable because the wrapped formatter is never mutated after init.
// ok: pocketcasts.unchecked-sendable-requires-justification
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

// Extension-based retroactive conformance is covered by the same token.
// ruleid: pocketcasts.unchecked-sendable-requires-justification
extension UnjustifiedBox2: @unchecked Sendable {}

final class UnjustifiedBox2 {
    var value: Int = 0
}
