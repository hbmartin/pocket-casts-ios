import UIKit

class LenticularOverlayView: UIView {
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let height: CGFloat = 2

        let color1 = UIColor(hex: "#119B00").withAlphaComponent(0.2)
        let color2 = UIColor.clear

        let patternSize = CGSize(width: height * 2, height: height)

        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: patternSize, format: format).image { _ in
            color1.setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: height, height: height)).fill()

            color2.setFill()
            UIBezierPath(rect: CGRect(x: height, y: 0, width: height, height: height)).fill()
        }

        let color = UIColor(patternImage: image)
        color.setFill()
        context.fill(rect)
    }
}
