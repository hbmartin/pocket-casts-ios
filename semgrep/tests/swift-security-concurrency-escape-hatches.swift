import Foundation

class EscapeHatchFixture {
    // ruleid: pocketcasts.nonisolated-unsafe-requires-justification
    nonisolated(unsafe) static var unjustifiedGlobal: Int = 0

    private static let stateLock = NSLock()

    // nonisolated(unsafe): all access is guarded by stateLock.
    // ok: pocketcasts.nonisolated-unsafe-requires-justification
    nonisolated(unsafe) static var justifiedByPrecedingComment: Int = 0

    /// Marked nonisolated(unsafe) because PassthroughSubject is internally thread-safe.
    // ok: pocketcasts.nonisolated-unsafe-requires-justification
    nonisolated(unsafe) static var justifiedByDocComment: Int = 0

    // ok: pocketcasts.nonisolated-unsafe-requires-justification
    nonisolated(unsafe) static let justifiedInline = NSObject() // nonisolated(unsafe): immutable lock token.

    // A comment that merely repeats the keyword with no reason justifies nothing.
    // nonisolated(unsafe)
    // ruleid: pocketcasts.nonisolated-unsafe-requires-justification
    nonisolated(unsafe) static var bareKeywordNoReason: Int = 0

    // A comment that does not reference the keyword is not greppable as a justification.
    // All access guarded by stateLock.
    // ruleid: pocketcasts.nonisolated-unsafe-requires-justification
    nonisolated(unsafe) static var commentWithoutKeyword: Int = 0
}
