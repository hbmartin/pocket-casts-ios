import Foundation

public enum DeviceUtil {
    // Gets the identifier from the system, such as "iPhone7,1"
    public static let identifier: String = {
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
    // Read via ProcessInfo rather than the main actor-isolated UIDevice so it stays callable from any thread.
    public static var systemVersion: String? {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.patchVersion > 0 {
            return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        }
        return "\(version.majorVersion).\(version.minorVersion)"
    }
}
