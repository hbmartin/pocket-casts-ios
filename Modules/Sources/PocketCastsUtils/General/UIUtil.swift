#if !os(tvOS)
    import UIKit

    public enum UIUtil {
        @MainActor
        public static func statusBarHeight(in window: UIWindow) -> CGFloat {
            window.windowScene?.statusBarManager?.statusBarFrame.height ?? 0
        }
    }
#endif
