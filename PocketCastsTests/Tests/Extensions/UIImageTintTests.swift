import CoreImage
import UIKit
import XCTest
@testable import PocketCastsUtils

final class UIImageTintTests: XCTestCase {

    func testTintedImageRendersCIImageBackedImages() throws {
        let ciImage = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = UIImage(ciImage: ciImage)

        XCTAssertNil(image.cgImage)

        let tintedImage = try XCTUnwrap(image.tintedImage(.red))
        XCTAssertEqual(tintedImage.size, image.size)
        XCTAssertNotNil(tintedImage.cgImage)
    }
}
