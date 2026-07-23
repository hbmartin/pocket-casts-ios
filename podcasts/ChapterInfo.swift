import AVFoundation
import Foundation
import PocketCastsUtils
import UIKit

// Instances are built single-threaded by the chapter parser and
// then handed over wholesale to the main-actor ChapterManager.
// @unchecked Sendable: post-hand-off reads and shouldPlay writes stay on the main actor.
nonisolated class ChapterInfo: Equatable, @unchecked Sendable {
    var title = ""
    var url: String?
    var startTime = CMTime(seconds: 0, preferredTimescale: 0)
    var image: UIImage?
    /// Remote artwork for chapters whose source carries a URL instead of embedded
    /// bytes (Podcast Index `img`, Podlove `image`). Fetched lazily; a successful
    /// fetch lands in `image`, which every artwork sink reads.
    var imageURL: URL?
    var isFirst = false
    var isLast = false
    var index = 0
    var duration: TimeInterval = 0
    var isHidden = false

    /// Should only be used for sync purposes, if reading for playback
    /// use `isPlayable()` instead
    var shouldPlay = true

    func isPlayable() -> Bool {
        #if APPCLIP
        return false
        #else
        shouldPlay
        #endif
    }

    static func == (lhs: ChapterInfo, rhs: ChapterInfo) -> Bool {
        lhs.title == rhs.title && lhs.startTime.seconds == rhs.startTime.seconds && lhs.duration == rhs.duration
    }
}
