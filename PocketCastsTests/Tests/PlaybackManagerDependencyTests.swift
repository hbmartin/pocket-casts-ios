import Dependencies
import XCTest

@testable import podcasts

@MainActor
final class PlaybackManagerDependencyTests: XCTestCase {
    func testDefaultValueIsSharedPlaybackManager() {
        withDependencies {
            $0.context = .live
        } operation: {
            @Dependency(\.playbackManager) var playbackManager
            XCTAssertTrue((playbackManager as AnyObject) === PlaybackManager.shared)
        }
    }

    func testOverridingWithMockInterceptsCalls() {
        let mock = PlaybackManagingMock()
        withDependencies {
            $0.playbackManager = mock
        } operation: {
            @Dependency(\.playbackManager) var playbackManager
            // `pause()` and `seekTo(time:)` are the protocol-extension overloads that mirror
            // PlaybackManager's default arguments; they must route into the mock's witnesses.
            playbackManager.pause()
            playbackManager.seekTo(time: 42)

            XCTAssertEqual(mock.pauseCalls, [true])
            XCTAssertEqual(mock.seekToTimes, [42])
            XCTAssertTrue((playbackManager as AnyObject) === mock)
        }
    }

    func testOverridingWithMockUsesStubbedValues() {
        let mock = PlaybackManagingMock()
        mock.playingStub = true
        mock.currentTimeStub = 12
        mock.durationStub = 60
        mock.upNextCountStub = 3

        withDependencies {
            $0.playbackManager = mock
        } operation: {
            @Dependency(\.playbackManager) var playbackManager
            XCTAssertTrue(playbackManager.playing())
            XCTAssertEqual(playbackManager.currentTime(), 12)
            XCTAssertEqual(playbackManager.duration(), 60)
            XCTAssertEqual(playbackManager.upNextCount(), 3)
        }
    }
}
