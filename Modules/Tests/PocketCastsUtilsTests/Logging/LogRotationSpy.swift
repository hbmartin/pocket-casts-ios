import Foundation

@testable import PocketCastsUtils

// @unchecked Sendable: test double; assertions only read state after awaiting the
// actor-isolated work that writes it.
final class LogRotationSpy: FileRotating, @unchecked Sendable {

    private(set) var rotationRequested = false

    func rotateFile(ifSizeExceeds: Int) {
        rotationRequested = true
    }
}
