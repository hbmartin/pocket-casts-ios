import UIKit
import XCTest
@testable import podcasts

final class PCSearchBarControllerTests: XCTestCase {

    func testInstallWithCollapsingBarExposesScrollableHeightConstraint() throws {
        let parent = UIViewController()
        let scrollView = UIScrollView()
        let searchController = TestSearchBarController()

        searchController.install(in: parent, attachedTo: scrollView, collapses: true)

        let heightConstraint = try XCTUnwrap(searchController.heightConstraint)
        XCTAssertEqual(heightConstraint.constant, 0)
        XCTAssertEqual(scrollView.contentInset.top, PCSearchBarController.defaultHeight)
        XCTAssertEqual(scrollView.contentOffset.y, -PCSearchBarController.defaultHeight)
    }

    func testInstallWithNonCollapsingBarKeepsDefaultHeightOutsideScrollingExtension() throws {
        let parent = UIViewController()
        let scrollView = UIScrollView()
        let searchController = TestSearchBarController()

        searchController.install(in: parent, attachedTo: scrollView, collapses: false)

        XCTAssertNil(searchController.heightConstraint)
        let installedHeightConstraint = try XCTUnwrap(
            searchController.view.constraints.first {
                ($0.firstItem as? UIView) === searchController.view && $0.firstAttribute == .height
            }
        )
        XCTAssertEqual(installedHeightConstraint.constant, PCSearchBarController.defaultHeight)
        XCTAssertEqual(scrollView.contentInset.top, PCSearchBarController.defaultHeight)
        XCTAssertEqual(scrollView.contentOffset.y, -PCSearchBarController.defaultHeight)
    }
}

private final class TestSearchBarController: PCSearchBarController {
    override func loadView() {
        view = UIView()
    }

    override func viewDidLoad() {}
}
