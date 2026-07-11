import Foundation
import Synchronization

@testable import PocketCastsUtils

final class LogRotationSpy: FileRotating {

    private let state = Mutex(false)

    var rotationRequested: Bool {
        state.withLock { $0 }
    }

    func rotateFile(ifSizeExceeds: Int) {
        state.withLock { $0 = true }
    }
}
