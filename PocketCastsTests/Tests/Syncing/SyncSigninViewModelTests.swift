import Foundation
import XCTest

@testable import PocketCastsServer
@testable import PocketCastsUtils
@testable import podcasts

@MainActor
final class SyncSigninViewModelTests: XCTestCase {
    func testTerminalSyncNotificationsCompleteSignInOnlyOnce() {
        let model = SyncSigninViewModel(coordinator: LoginCoordinator())
        var completionCount = 0
        model.onCompleted = { completionCount += 1 }
        model.onAppear(loginAgain: false)
        defer { model.onDisappear() }

        NotificationCenter.postOnMainThread(SyncCompleted())
        NotificationCenter.postOnMainThread(SyncFailed())
        NotificationCenter.postOnMainThread(PodcastRefreshFailed())

        XCTAssertEqual(completionCount, 1)
    }
}
