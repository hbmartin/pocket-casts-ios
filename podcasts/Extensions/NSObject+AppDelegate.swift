import Foundation

extension NSObject {
    @MainActor
    func appDelegate() -> AppDelegate? {
        UIApplication.shared.delegate as? AppDelegate
    }
}
