import UIKit

class ThemeableImageView: UIImageView {
    var imageNameFunc: (() -> String)? {
        didSet {
            updateImage()
        }
    }

    var imageStyle: ThemeStyle? {
        didSet {
            updateImage()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }

    private var themeToken: NotificationCenter.ObservationToken?

    deinit {
        let token = themeToken
        NotificationCenter.default.removeObserver(self)
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func setup() {
        updateImage()

        themeToken = NotificationCenter.default.addObserver(for: ThemeChanged.self) { [weak self] _ in
            self?.themeDidChange()
        }
    }

    func themeDidChange() {
        updateImage()
    }

    private func updateImage() {
        if let imageName = imageNameFunc {
            image = UIImage(named: imageName())
        } else if let imageStyle, let currentImage = image {
            image = currentImage.tintedImage(AppTheme.colorForStyle(imageStyle))
        }
    }
}
