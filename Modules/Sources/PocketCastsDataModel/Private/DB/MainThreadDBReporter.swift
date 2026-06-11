#if DEBUG
import Foundation
import PocketCastsUtils

/// Logs database access that happens on the main thread, deduplicated per call site,
/// so offenders can be found and moved to background queues. DEBUG builds only.
enum MainThreadDBReporter {
    private static let lock = NSLock()
    private static var reportedCallers = Set<String>()

    static func reportIfNeeded(operation: StaticString = #function) {
        guard Thread.isMainThread, FeatureFlag.logMainThreadDatabaseAccess.enabled else { return }

        let symbols = Array(Thread.callStackSymbols.dropFirst(2).prefix(10))
        // The interesting frame is the first one outside this module — the app-level call site.
        let caller = symbols.first { !$0.contains("PocketCastsDataModel") } ?? symbols.first ?? "unknown"

        lock.lock()
        let isNewCaller = reportedCallers.insert(caller).inserted
        lock.unlock()
        guard isNewCaller else { return }

        FileLog.shared.addMessage("Main-thread database \(operation) from:\n\(symbols.joined(separator: "\n"))")
    }
}
#endif
