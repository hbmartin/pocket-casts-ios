import UIKit

public extension UIImage {
    func tintedImage(_ color: UIColor) -> UIImage? {
        // lets tint the icon - assumes your icons are black
        guard cgImage != nil else { return nil }

        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false

        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        return UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            let context = rendererContext.cgContext

            // draw alpha-mask
            context.setBlendMode(.normal)
            draw(in: rect)

            // draw tint color, preserving alpha values of original image
            context.setBlendMode(.sourceIn)
            color.setFill()
            context.fill(rect)
        }
    }


    /// Resize the image using the aspect ration to the given size
    /// Specify the displayScale to set the UIImage.scale factor of the image
    func resizeProportionally(to newSize: CGSize, displayScale: CGFloat = 0) -> UIImage {
        let widthRatio = newSize.width / size.width
        let heightRatio = newSize.height / size.height

        let scaleFactor = min(widthRatio, heightRatio)
        let scaledImageSize = CGSize(
            width: size.width * scaleFactor,
            height: size.height * scaleFactor
        )

        // If it fails, just return the same image
        guard let resized = resized(to: scaledImageSize, displayScale: displayScale) else {
            return self
        }

        return resized
    }

    func resized(to newSize: CGSize, displayScale: CGFloat = 0) -> UIImage? {
        guard newSize.width > 0, newSize.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = displayScale > 0 ? displayScale : scale
        format.opaque = false

        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
