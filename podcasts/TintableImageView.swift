import UIKit

class TintableImageView: UIImageView {
    override init(image: UIImage?) {
        super.init(image: image)

        super.image = image?.tintedImage(tintColor)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        super.image = image?.tintedImage(tintColor)
    }

    override nonisolated func awakeFromNib() {
        super.awakeFromNib()

        // awakeFromNib is nonisolated in its ObjC declaration, but views always wake on the main thread
        MainActor.assumeIsolated {
            super.image = image?.tintedImage(tintColor)
        }
    }

    override var tintColor: UIColor! {
        didSet {
            super.image = image?.tintedImage(tintColor)
        }
    }
}
