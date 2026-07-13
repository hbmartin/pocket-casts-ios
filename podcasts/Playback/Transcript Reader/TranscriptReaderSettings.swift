import Foundation
import UIKit

/// The reader's Aa control cycles through these sizes; the point size is the
/// base body size before Dynamic Type scaling.
nonisolated enum TranscriptReaderTextSize: Int, CaseIterable, Sendable {
    case small = 0
    case medium = 1
    case large = 2
    case extraLarge = 3

    var pointSize: CGFloat {
        switch self {
        case .small: 15
        case .medium: 17
        case .large: 20
        case .extraLarge: 23
        }
    }

    var next: TranscriptReaderTextSize {
        TranscriptReaderTextSize(rawValue: rawValue + 1) ?? .small
    }
}

extension Settings {
    private static let transcriptReaderTextSizeKey = "TranscriptReaderTextSize"
    private static let transcriptReaderSerifFontKey = "TranscriptReaderUsesSerifFont"

    static var transcriptReaderTextSize: TranscriptReaderTextSize {
        get {
            guard UserDefaults.standard.object(forKey: transcriptReaderTextSizeKey) != nil else { return .medium }
            return TranscriptReaderTextSize(rawValue: UserDefaults.standard.integer(forKey: transcriptReaderTextSizeKey)) ?? .medium
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: transcriptReaderTextSizeKey)
        }
    }

    /// The reader defaults to a serif face, matching the transcript view
    /// controller's serif body styling.
    static var transcriptReaderUsesSerifFont: Bool {
        get {
            UserDefaults.standard.object(forKey: transcriptReaderSerifFontKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: transcriptReaderSerifFontKey)
        }
    }
}
