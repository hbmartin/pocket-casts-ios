import Foundation
import PocketCastsUtils

/// A storage type for a `Codable` settings value.
/// This handles storage to `UserDefaults` (optionally overridable)
@dynamicMemberLookup
public final class SettingsStore<Value: JSONCodable> {
    public let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard, key: String, value: Value) {
        self.userDefaults = userDefaults
        _settings = CodableStore(wrappedValue: value, key)
    }

    @CodableStore var settings: Value

    /// Access any property from `settings` without direct access to settings.
    /// Avoids having to type `appSettings.settings` and allows for future ObservableObject / publisher adoption in this method
    public subscript<T>(dynamicMember keyPath: WritableKeyPath<Value, T>) -> T {
        get {
            settings[keyPath: keyPath]
        }
        set {
            settings[keyPath: keyPath] = newValue
        }
    }
}

extension SettingsStore {
    /// Round-trippable JSON of the whole settings value, `@ModifiedDate` wrappers
    /// included — the payload user-facing backup writes alongside the database.
    public func exportSettingsJSON() -> Data? {
        settings.jsonData
    }

    /// Replaces the stored settings with the decoded JSON (the restore counterpart of
    /// `exportSettingsJSON`). Returns false when the data doesn't decode as `Value`.
    @discardableResult
    public func importSettingsJSON(_ data: Data) -> Bool {
        guard let imported = try? Value.encodedObject(Value.self, from: data) else { return false }
        settings = imported
        return true
    }

    /// Access any property from `settings` without direct access to settings.
    /// Avoids having to type `appSettings.settings` and allows for future ObservableObject / publisher adoption in this method
    subscript<T>(modifiedDate keyPath: WritableKeyPath<Value, ModifiedDate<T>>) -> ModifiedDate<T> {
        get {
            settings[keyPath: keyPath]
        }
        set {
            settings[keyPath: keyPath] = newValue
        }
    }

    public func update<T: RawRepresentable>(_ keyPath: WritableKeyPath<Value, ModifiedDate<T>>, value: T.RawValue) {
        if let representable = T(rawValue: value) {
            self.update(keyPath, value: representable)
        }
    }

    public func update<T: Equatable & Codable>(_ modifiedKeyPath: WritableKeyPath<Value, ModifiedDate<T>>, value: T) {
        let openLinksValue = value
        if openLinksValue != self[dynamicMember: modifiedKeyPath].wrappedValue {
            self[modifiedDate: modifiedKeyPath].projectedValue = ModifiedDate(wrappedValue: openLinksValue)
        }
    }
}
