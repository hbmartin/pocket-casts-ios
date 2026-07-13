import Foundation

class IsolatedDeinitFixture {
    // ruleid: pocketcasts.isolated-deinit-requires-justification
    isolated deinit {
        performWork()
    }
}

class JustifiedByPrecedingComment {
    // isolated deinit: view controllers deallocate on the main actor; deinit tears down isolated observers
    // ok: pocketcasts.isolated-deinit-requires-justification
    isolated deinit {
        performWork()
    }
}

class JustifiedInline {
    // ok: pocketcasts.isolated-deinit-requires-justification
    isolated deinit { // isolated deinit: dies on main, touches isolated state
        performWork()
    }
}

class NonisolatedDeinitIsFine {
    // ok: pocketcasts.isolated-deinit-requires-justification
    nonisolated deinit {
        performWork()
    }
}
