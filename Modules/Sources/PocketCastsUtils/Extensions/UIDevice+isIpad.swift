import UIKit

extension UIDevice {
    public func isiPad() -> Bool {
        userInterfaceIdiom == .pad
    }
}
