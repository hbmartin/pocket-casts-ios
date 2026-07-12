import SnapshotTesting
import SwiftUI
import XCTest
@testable import podcasts

/// Themed snapshot coverage for dependency-light app-target SwiftUI views
/// (program item H2): every view renders under all nine app themes, one
/// reference image per theme. New feature views should add themselves here
/// (or in a sibling file) as they land.
@MainActor
final class AppThemedViewSnapshotTests: XCTestCase {
    func testPocketCastsLogoPill() {
        assertAppThemedSnapshots(
            of: PocketCastsLogoPill(),
            layout: .fixed(width: 200, height: 60)
        )
    }

    func testTrimPlayButton() {
        assertAppThemedSnapshots(
            of: TrimPlayButton(isPlaying: .constant(false)),
            layout: .fixed(width: 80, height: 80)
        )
    }

    func testInterestButtonSelectedAndNot() {
        assertAppThemedSnapshots(
            of: VStack(spacing: 8) {
                InterestButton(name: "Technology", icon: nil, isSelected: false, style: .interest, action: nil)
                InterestButton(name: "Technology", icon: nil, isSelected: true, style: .interest, action: nil)
            },
            layout: .fixed(width: 220, height: 120)
        )
    }

    func testColorSelectRow() {
        assertAppThemedSnapshots(
            of: ColorSelectRow(model: FolderModel()),
            layout: .fixed(width: 340, height: 130)
        )
    }

    func testProfileInfoLabels() {
        assertAppThemedSnapshots(
            of: ProfileInfoLabels(
                profile: .init(isLoggedIn: true, email: "listener@example.com"),
                alignment: .leading,
                spacing: 8
            ),
            layout: .fixed(width: 300, height: 90)
        )
    }

    func testModalCloseButton() {
        assertAppThemedSnapshots(
            of: ModalCloseButton(action: {}),
            layout: .fixed(width: 60, height: 60)
        )
    }

    func testRoundedSubscribeButton() {
        assertAppThemedSnapshots(
            of: RoundedSubscribeButtonView(podcastUuid: "snapshot-test-uuid", source: .unknown),
            layout: .fixed(width: 120, height: 60)
        )
    }
}
