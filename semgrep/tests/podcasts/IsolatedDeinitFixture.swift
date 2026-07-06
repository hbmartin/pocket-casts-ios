import Foundation

class IsolatedDeinitFixture {
    // ruleid: pocketcasts.isolated-deinit-requires-justification
    isolated deinit {
        print("unjustified")
    }
}

class JustifiedByPrecedingComment {
    // isolated deinit: view controllers deallocate on the main actor; deinit tears down isolated observers
    // ok: pocketcasts.isolated-deinit-requires-justification
    isolated deinit {
        print("justified")
    }
}

class JustifiedInline {
    // ok: pocketcasts.isolated-deinit-requires-justification
    isolated deinit { // isolated deinit: dies on main, touches isolated state
        print("justified inline")
    }
}

class NonisolatedDeinitIsFine {
    // ok: pocketcasts.isolated-deinit-requires-justification
    nonisolated deinit {
        print("nonisolated deinit never hops executors")
    }
}
