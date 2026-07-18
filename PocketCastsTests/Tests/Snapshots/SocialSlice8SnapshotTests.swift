import PocketCastsServer
import SnapshotTesting
import SwiftUI
import XCTest

@testable import podcasts

/// Themed snapshot coverage for Slice 8 (social push): the per-type toggles
/// screen in its all-on default and a mixed state. Fixture VMs never save.
@MainActor
final class SocialSlice8SnapshotTests: XCTestCase {
    func testSocialNotificationSettingsAllOn() {
        assertAppThemedSnapshots(
            of: NavigationView {
                SocialNotificationSettingsView(viewModel: SocialNotificationSettingsViewModel(fixtureMask: 0))
            }.navigationViewStyle(.stack),
            layout: .fixed(width: 390, height: 520)
        )
    }

    func testSocialNotificationSettingsMixed() {
        // New-follower and reply pushes off; the rest on.
        let mask = SocialPushType.newFollower.bit | SocialPushType.commentReply.bit
        assertAppThemedSnapshots(
            of: NavigationView {
                SocialNotificationSettingsView(viewModel: SocialNotificationSettingsViewModel(fixtureMask: mask))
            }.navigationViewStyle(.stack),
            layout: .fixed(width: 390, height: 520)
        )
    }
}
