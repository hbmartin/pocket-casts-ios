import SwiftUI
import Foundation
import PocketCastsUtils

enum ExplicitBadgeHelper {
    static let badgeSize: CGFloat = 11

    private static let imageCacheLock = NSLock()
    // nonisolated(unsafe): guarded by imageCacheLock
    nonisolated(unsafe) private static var imageCache: [Theme.ThemeType: UIImage] = [:]

    static func badgeImage(for theme: Theme.ThemeType? = nil) -> UIImage {
        let resolvedTheme = theme ?? Theme.sharedTheme.nonisolatedActiveTheme
        imageCacheLock.lock()
        if let cached = imageCache[resolvedTheme] {
            imageCacheLock.unlock()
            return cached
        }
        imageCacheLock.unlock()

        let image = renderBadgeImage(for: resolvedTheme)

        imageCacheLock.lock()
        imageCache[resolvedTheme] = image
        imageCacheLock.unlock()

        return image
    }

    private static func renderBadgeImage(for theme: Theme.ThemeType) -> UIImage {
        makeBadgeImage(for: theme)
    }

    private static func makeBadgeImage(for theme: Theme.ThemeType) -> UIImage {
        let bgColor = ThemeColor.primaryIcon03(for: theme)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: badgeSize, height: badgeSize))
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: CGSize(width: badgeSize, height: badgeSize))
            bgColor.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 2).fill()

            let text = "E" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 7, weight: .heavy),
                .foregroundColor: UIColor.white,
            ]
            let textSize = text.size(withAttributes: attrs)
            let textRect = CGRect(
                x: (badgeSize - textSize.width) / 2,
                y: (badgeSize - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attrs)
        }
    }

    static func inlineTitle(_ title: String, isExplicit: Bool, theme: Theme.ThemeType? = nil) -> Text {
        if FeatureFlag.showExplicitBadges.enabled, isExplicit {
            return Text(title) + Text(" ") + Text(Image(uiImage: badgeImage(for: theme))).baselineOffset(-1).accessibilityLabel(L10n.podcastExplicitContent)
        }
        return Text(title)
    }

    static func attributedTitle(_ title: String, font: UIFont, theme: Theme.ThemeType? = nil) -> NSAttributedString {
        guard FeatureFlag.showExplicitBadges.enabled else {
            return NSAttributedString(string: title, attributes: [.font: font])
        }
        let result = NSMutableAttributedString(string: title + " ", attributes: [.font: font])
        let image = badgeImage(for: theme)

        let attachment = NSTextAttachment()
        attachment.image = image
        let yOffset = (font.capHeight - badgeSize) / 2
        attachment.bounds = CGRect(x: 0, y: yOffset, width: badgeSize, height: badgeSize)
        result.append(NSAttributedString(attachment: attachment))

        return result
    }
}
