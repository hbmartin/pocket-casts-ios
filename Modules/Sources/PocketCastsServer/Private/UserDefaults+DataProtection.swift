import Foundation
import UIKit

extension UserDefaults {
    /// Callable from any thread; hops to the main actor for the UIApplication read.
    static func isProtectedDataAvailable() -> Bool? {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { UIApplication.shared.isProtectedDataAvailable }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { UIApplication.shared.isProtectedDataAvailable }
        }
    }
}
