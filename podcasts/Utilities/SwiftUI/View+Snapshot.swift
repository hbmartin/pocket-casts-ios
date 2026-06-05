import SwiftUI
import UIKit

extension View {
    @MainActor
    func snapshot(scale: CGFloat = 2) -> UIImage {
        let renderer = ImageRenderer(content: self)
        renderer.scale = scale
        guard let renderedImage = renderer.uiImage else {
            assertionFailure("Rendered ImageRenderer image should not be nil")
            return UIImage()
        }
        return renderedImage
    }
}
