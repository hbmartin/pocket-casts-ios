import Foundation
import PocketCastsServer

/// How an eyes-free highlight capture is confirmed (Highlights program S3).
/// A gentle haptic always plays; this picks the audible layer. Synced as the
/// `highlight_confirmation_style` app setting (fork proto field 1017).
enum HighlightConfirmationStyle: Int32, CaseIterable {
    case sound = 0
    case soundAndSpoken = 1
    case spoken = 2
    case none = 3

    var playsSound: Bool { self == .sound || self == .soundAndSpoken }
    var speaks: Bool { self == .soundAndSpoken || self == .spoken }

    var displayableTitle: String {
        switch self {
        case .sound: L10n.highlightConfirmationSound
        case .soundAndSpoken: L10n.highlightConfirmationSoundSpoken
        case .spoken: L10n.highlightConfirmationSpoken
        case .none: L10n.highlightConfirmationNone
        }
    }
}

extension Settings {
    /// The capture-confirmation style (synced). Unknown synced values decode
    /// as the default so a newer client's addition can't crash an older one.
    static var highlightConfirmationStyle: HighlightConfirmationStyle {
        get { HighlightConfirmationStyle(rawValue: SettingsStore.appSettings.highlightConfirmationStyle) ?? .sound }
        set { SettingsStore.appSettings.highlightConfirmationStyle = newValue.rawValue }
    }
}
