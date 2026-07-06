import UIKit

/// Colors for highlighting transcript search matches, matching the interactive
/// button styling when shown from an episode and the player palette otherwise.
nonisolated enum TranscriptSearchHighlightStyle {
    static func attributes(showFromEpisode: Bool, isCurrent: Bool) -> [NSAttributedString.Key: Any] {
        if showFromEpisode {
            return [
                .backgroundColor: ThemeColor.primaryInteractive01().withAlphaComponent(isCurrent ? 1 : 0.2),
                .foregroundColor: isCurrent ? ThemeColor.primaryUi01() : ThemeColor.primaryInteractive01()
            ]
        }
        return [
            .backgroundColor: UIColor.white.withAlphaComponent(isCurrent ? 1 : 0.4),
            .foregroundColor: isCurrent ? UIColor.black : ThemeColor.playerContrast01()
        ]
    }
}
