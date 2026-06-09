import Foundation
import UIKit

extension UserDefaults {
    static func isProtectedDataAvailable() -> Bool? {
        return UIApplication.shared.isProtectedDataAvailable
    }
}
