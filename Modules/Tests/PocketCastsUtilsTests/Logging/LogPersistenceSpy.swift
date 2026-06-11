import Foundation

@testable import PocketCastsUtils

// @unchecked Sendable: test double; assertions only read state after awaiting the
// actor-isolated work that writes it.
final class LogPersistenceSpy: PersistentTextWriting, @unchecked Sendable {

    private(set) var textWrittenToLog = false
    private(set) var writeCount: UInt = 0
    private(set) var lastWrittenChunk: String?

    func write(_ text: String) {
        textWrittenToLog = true
        writeCount += 1
        lastWrittenChunk = text
    }
}
