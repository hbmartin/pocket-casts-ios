import Foundation
    import UIKit

public enum DeviceUtil {
    // Gets the identifier from the system, such as "iPhone7,1"
    public static var identifier: String = {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)

        let identifier = mirror.children.reduce(into: "") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            identifier += String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }()

    // The current version of the operating system (e.g. 8.4 or 9.2).
    public static var systemVersion: String? {
            return UIDevice.current.systemVersion
    }
}
