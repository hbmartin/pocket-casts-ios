import AVFoundation
import Foundation
import UIKit

/// Builds burned-in captions for shared clips (Highlights S13): pure cue →
/// caption math plus the Core Animation layer tree the export composition
/// renders. Cue-level timing (no word karaoke): each caption shows for its
/// cue's span, clamped to a readable minimum.
nonisolated enum CaptionOverlayBuilder {
    struct Caption: Equatable, Sendable {
        /// Seconds from the clip's start.
        let start: TimeInterval
        let duration: TimeInterval
        let text: String
    }

    /// Minimum on-screen time per caption; very short cues extend into the gap.
    static let minimumDisplay: TimeInterval = 1.2

    /// Maps transcript cues to clip-relative captions: cues intersecting
    /// `[clipStart, clipEnd]` (transcript time domain == clip's audio domain),
    /// shifted to clip time and clamped to the clip bounds.
    static func captions(
        cues: [TranscriptCue],
        plainText: String,
        clipStart: TimeInterval,
        clipDuration: TimeInterval
    ) -> [Caption] {
        let clipEnd = clipStart + clipDuration
        let fullText = plainText as NSString

        let intersecting = cues
            .filter { $0.endTime > clipStart && $0.startTime < clipEnd }
            .sorted { $0.startTime < $1.startTime }

        var out: [Caption] = []
        for (index, cue) in intersecting.enumerated() {
            guard cue.characterRange.location != NSNotFound,
                  NSMaxRange(cue.characterRange) <= fullText.length else { continue }
            let text = HighlightExcerptBuilder.normalizedWhitespace(fullText.substring(with: cue.characterRange))
            guard !text.isEmpty else { continue }

            let start = max(0, cue.startTime - clipStart)
            var end = min(clipDuration, cue.endTime - clipStart)
            // Readability floor: extend short cues into the following gap.
            let nextStart = index + 1 < intersecting.count
                ? max(0, intersecting[index + 1].startTime - clipStart)
                : clipDuration
            end = min(max(end, start + minimumDisplay), nextStart, clipDuration)
            guard end > start else { continue }

            out.append(Caption(start: start, duration: end - start, text: text))
        }
        return out
    }

    /// The overlay layer tree for `AVVideoCompositionCoreAnimationTool`:
    /// bottom-anchored caption text with a soft scrim, one layer per caption,
    /// revealed by opacity animations on the composition timeline. Detached
    /// layers are safe to build off-main; AVFoundation renders the tree on its
    /// own thread.
    static func overlayLayer(captions: [Caption], renderSize: CGSize) -> CALayer {
        let overlay = CALayer()
        overlay.frame = CGRect(origin: .zero, size: renderSize)

        let fontSize = max(12, renderSize.width * 0.045)
        let inset = renderSize.width * 0.06
        let captionHeight = fontSize * 3.2

        for caption in captions {
            let textLayer = CATextLayer()
            textLayer.string = caption.text
            textLayer.font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
            textLayer.fontSize = fontSize
            textLayer.foregroundColor = UIColor.white.cgColor
            textLayer.backgroundColor = UIColor.black.withAlphaComponent(0.55).cgColor
            textLayer.cornerRadius = fontSize * 0.4
            textLayer.masksToBounds = true
            textLayer.alignmentMode = .center
            textLayer.isWrapped = true
            textLayer.truncationMode = .end
            textLayer.contentsScale = 3
            textLayer.frame = CGRect(
                x: inset,
                y: renderSize.height * 0.06,
                width: renderSize.width - inset * 2,
                height: captionHeight
            )
            textLayer.opacity = 0

            let reveal = CAKeyframeAnimation(keyPath: "opacity")
            reveal.beginTime = caption.start == 0 ? AVCoreAnimationBeginTimeAtZero : caption.start
            reveal.duration = caption.duration
            reveal.keyTimes = [0, 0.02, 0.98, 1]
            reveal.values = [0, 1, 1, 0]
            reveal.isRemovedOnCompletion = false
            reveal.fillMode = .forwards
            textLayer.add(reveal, forKey: "captionReveal")

            overlay.addSublayer(textLayer)
        }

        return overlay
    }
}
