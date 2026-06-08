import Foundation

public struct RemoteConfigValueStore {
    public static let keyPrefix = "remote-config-"

    private let store: UserDefaults
    private let keyPrefix: String

    public init(store: UserDefaults = .standard, keyPrefix: String = Self.keyPrefix) {
        self.store = store
        self.keyPrefix = keyPrefix
    }

    public static func key(for key: String) -> String {
        "\(keyPrefix)\(key)"
    }

    public func bool(forKey key: String) -> Bool? {
        guard let value = object(forKey: key) else {
            return nil
        }

        if let bool = value as? Bool {
            return bool
        }

        if let number = value as? NSNumber {
            return number.boolValue
        }

        if let string = value as? String {
            switch string.lowercased() {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                return nil
            }
        }

        return nil
    }

    public func double(forKey key: String) -> Double? {
        guard let value = object(forKey: key) else {
            return nil
        }

        if let double = value as? Double {
            return double
        }

        if let number = value as? NSNumber {
            return number.doubleValue
        }

        if let string = value as? String {
            return Double(string)
        }

        return nil
    }

    public func int(forKey key: String) -> Int? {
        guard let value = object(forKey: key) else {
            return nil
        }

        if let int = value as? Int {
            return int
        }

        if let number = value as? NSNumber {
            return number.intValue
        }

        if let string = value as? String {
            return Int(string)
        }

        return nil
    }

    private func object(forKey key: String) -> Any? {
        store.object(forKey: "\(keyPrefix)\(key)")
    }
}
