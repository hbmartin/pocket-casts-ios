import PocketCastsUtils
import UIKit

class ThemeSecondaryIcon: UIImageView {
    var originalImage: UIImage?

    override nonisolated func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated {
            originalImage = image

            themeToken = NotificationCenter.default.addObserver(for: ThemeChanged.self) { [weak self] _ in
                self?.setTintColorForTheme()
            }
            setTintColorForTheme()
        }
    }

    private var themeToken: NotificationCenter.ObservationToken?

    deinit {
        let token = themeToken
        NotificationCenter.default.removeObserver(self)
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func setTintColorForTheme() {
        image = originalImage?.tintedImage(ThemeColor.primaryIcon02())
    }
}
