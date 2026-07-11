import Foundation
import Synchronization

@testable import PocketCastsUtils

final class LogPersistenceSpy: PersistentTextWriting {

    private struct State {
        var textWrittenToLog = false
        var writeCount: UInt = 0
        var lastWrittenChunk: String?
    }

    private let state = Mutex(State())

    var textWrittenToLog: Bool { state.withLock { $0.textWrittenToLog } }
    var writeCount: UInt { state.withLock { $0.writeCount } }
    var lastWrittenChunk: String? { state.withLock { $0.lastWrittenChunk } }

    func write(_ text: String) {
        state.withLock {
            $0.textWrittenToLog = true
            $0.writeCount += 1
            $0.lastWrittenChunk = text
        }
    }
}
