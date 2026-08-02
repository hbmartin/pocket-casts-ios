import Foundation

class HapticsHelper {
    class func triggerSkipBackHaptic() {
        triggerImpactOccurredHaptic(style: .medium)
    }

    class func triggerSkipForwardHaptic() {
        triggerImpactOccurredHaptic(style: .medium)
    }

    class func triggerSubscribedHaptic() {
        triggerSuccessHaptic()
    }

    /// Fires on every highlight capture (Highlights program S3) so eyes-free
    /// saves are felt even when the audible confirmation is off.
    class func triggerHighlightCapturedHaptic() {
        triggerSuccessHaptic()
    }

    class func triggerStarHaptic() {
        triggerImpactOccurredHaptic(style: .light)
    }

    class func triggerPlayPauseHaptic() {
        triggerImpactOccurredHaptic(style: .light)
    }

    class func triggerRearrangeHaptic() {
        triggerImpactOccurredHaptic(style: .light)
    }

    class func triggerPullToRefreshHaptic() {
        triggerImpactOccurredHaptic(style: .heavy)
    }

    // Haptics can be triggered from playback code off the main thread; the
    // feedback generators are main-actor UIKit objects, so hop before touching them
    private class func triggerImpactOccurredHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        Task { @MainActor in
            let feedbackGenerator = UIImpactFeedbackGenerator(style: style)
            feedbackGenerator.impactOccurred()
        }
    }

    private class func triggerSuccessHaptic() {
        Task { @MainActor in
            let feedbackGenerator = UINotificationFeedbackGenerator()
            feedbackGenerator.notificationOccurred(.success)
        }
    }
}
