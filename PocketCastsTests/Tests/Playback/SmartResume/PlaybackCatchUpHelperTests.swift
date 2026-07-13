import Foundation
import Synchronization
import XCTest
@testable import podcasts
import PocketCastsDataModel
@testable import PocketCastsServer

/// First tests for the catch-up helper: injected suite defaults and a mock
/// analyzer isolate Smart Resume's precompute-at-pause pipeline (request →
/// guarded persistence → per-tier lookup at resume).
@MainActor
final class PlaybackCatchUpHelperTests: XCTestCase {
    // mirrors of the helper's private persistence keys, asserted on directly
    private let snapCandidatesKey = "lastPauseSnapCandidates"
    private let pauseTimeKey = "lastPauseTime"

    private var helper: PlaybackCatchUpHelper!
    private var analyzer: MockResumeSnapAnalyzer!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var previousAppSettings: SettingsStore<AppSettings>!
    private var episode: Episode!
    private var downloadedFilePath: String!

    override func setUp() async throws {
        try await super.setUp()

        suiteName = "PlaybackCatchUpHelperTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        previousAppSettings = SettingsStore.appSettings
        SettingsStore.appSettings = SettingsStore(userDefaults: defaults, key: "app_settings", value: AppSettings.defaults)
        setIntelligentResumption(true)

        analyzer = MockResumeSnapAnalyzer()
        helper = PlaybackCatchUpHelper(analyzer: analyzer, defaults: defaults)

        var episode = Episode()
        episode.uuid = "catch-up-\(UUID().uuidString)"
        episode.episodeStatus = DownloadStatus.downloaded.rawValue
        episode.fileType = "audio/mp3"
        self.episode = episode

        // downloaded(pathFinder:) needs a real file where DownloadManager points
        downloadedFilePath = DownloadManager.shared.pathForEpisode(episode)
        try FileManager.default.createDirectory(atPath: (downloadedFilePath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: downloadedFilePath, contents: Data(repeating: 0, count: 64))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: downloadedFilePath)
        defaults.removePersistentDomain(forName: suiteName)
        SettingsStore.appSettings = previousAppSettings

        helper = nil
        analyzer = nil
        defaults = nil
        suiteName = nil
        previousAppSettings = nil
        episode = nil
        downloadedFilePath = nil

        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Sets the setting in both storage paths so these tests hold regardless of
    /// the newSettingsStorage flag state.
    private func setIntelligentResumption(_ enabled: Bool) {
        SettingsStore.appSettings.intelligentResumption = enabled
        defaults.set(enabled, forKey: Constants.UserDefaults.intelligentPlaybackResumption)
    }

    /// Rewinds the stored pause timestamp so adjustStartTimeIfNeeded sees the
    /// given elapsed time since the pause.
    private func setPause(elapsed: TimeInterval) {
        defaults.set(Date(timeIntervalSinceNow: -elapsed), forKey: pauseTimeKey)
    }

    // MARK: - Analysis requests

    func testPauseRequestsAnalysisForAllTiers() throws {
        helper.playbackDidPause(of: episode, playedUpTo: 600)

        XCTAssertEqual(analyzer.requestCount, 1)
        XCTAssertEqual(analyzer.lastTargets, [590, 585, 570])
        XCTAssertEqual(try XCTUnwrap(analyzer.lastFileURL).path, downloadedFilePath)
    }

    func testNonPositiveTargetsAreDropped() {
        helper.playbackDidPause(of: episode, playedUpTo: 12)

        XCTAssertEqual(analyzer.lastTargets, [2], "the 15s and 30s tiers start before the episode does")
    }

    func testAnalyzerNotCalledWhenSettingOff() {
        setIntelligentResumption(false)

        helper.playbackDidPause(of: episode, playedUpTo: 600)

        XCTAssertEqual(analyzer.requestCount, 0)
    }

    func testAnalyzerNotCalledForVideoEpisode() {
        episode.fileType = "video/mp4"

        helper.playbackDidPause(of: episode, playedUpTo: 600)

        XCTAssertEqual(analyzer.requestCount, 0)
    }

    func testAnalyzerNotCalledWhenNotDownloaded() {
        episode.episodeStatus = DownloadStatus.notDownloaded.rawValue

        helper.playbackDidPause(of: episode, playedUpTo: 600)

        XCTAssertEqual(analyzer.requestCount, 0)
    }

    func testAnalyzerNotCalledNearEpisodeStart() {
        helper.playbackDidPause(of: episode, playedUpTo: 8)

        XCTAssertEqual(analyzer.requestCount, 0)
    }

    // MARK: - Tier lookup at resume

    func testSnappedTimeUsedForEachTier() throws {
        helper.playbackDidPause(of: episode, playedUpTo: 600)
        try XCTUnwrap(analyzer.completion(at: 0))([590: 589.5, 585: 584.2, 570: 570.6])

        setPause(elapsed: 6.minutes)
        XCTAssertEqual(helper.adjustStartTimeIfNeeded(for: episode, playedUpTo: 600), 589.5, "the 10s tier should use its snapped candidate")

        setPause(elapsed: 2.hours)
        XCTAssertEqual(helper.adjustStartTimeIfNeeded(for: episode, playedUpTo: 600), 584.2, "the 15s tier should use its snapped candidate")

        setPause(elapsed: 25.hours)
        XCTAssertEqual(helper.adjustStartTimeIfNeeded(for: episode, playedUpTo: 600), 570.6, "the 30s tier should use its snapped candidate")
    }

    func testRawRewindWhenNoCandidatesFound() throws {
        helper.playbackDidPause(of: episode, playedUpTo: 600)
        try XCTUnwrap(analyzer.completion(at: 0))([:])

        setPause(elapsed: 6.minutes)

        XCTAssertEqual(helper.adjustStartTimeIfNeeded(for: episode, playedUpTo: 600), 590)
        XCTAssertNil(defaults.dictionary(forKey: snapCandidatesKey), "an empty analysis result should not be persisted")
    }

    func testRawRewindWhenSnapTooFarFromRawPosition() throws {
        helper.playbackDidPause(of: episode, playedUpTo: 600)
        try XCTUnwrap(analyzer.completion(at: 0))([590: 585, 585: 584.2, 570: 570.6])

        setPause(elapsed: 6.minutes)

        XCTAssertEqual(helper.adjustStartTimeIfNeeded(for: episode, playedUpTo: 600), 590, "a snap more than 2.5s from the raw position must be ignored")
    }

    func testRawRewindWhenMissingTierCandidate() throws {
        helper.playbackDidPause(of: episode, playedUpTo: 600)
        try XCTUnwrap(analyzer.completion(at: 0))([590: 589.5])

        setPause(elapsed: 25.hours)

        XCTAssertEqual(helper.adjustStartTimeIfNeeded(for: episode, playedUpTo: 600), 570, "no 30s-tier candidate means the raw rewind applies")
    }

    // MARK: - Persistence guard

    func testStaleCompletionIsDiscarded() throws {
        helper.playbackDidPause(of: episode, playedUpTo: 600)
        helper.playbackDidPause(of: episode, playedUpTo: 700)

        // the first pause's analysis finishing late must not overwrite the second pause's state
        try XCTUnwrap(analyzer.completion(at: 0))([590: 589.5])

        XCTAssertNil(defaults.dictionary(forKey: snapCandidatesKey))

        setPause(elapsed: 6.minutes)
        XCTAssertEqual(helper.adjustStartTimeIfNeeded(for: episode, playedUpTo: 700), 690)
    }

    func testCandidatesClearedOnNewPause() throws {
        helper.playbackDidPause(of: episode, playedUpTo: 600)
        try XCTUnwrap(analyzer.completion(at: 0))([590: 589.5])
        XCTAssertNotNil(defaults.dictionary(forKey: snapCandidatesKey))

        helper.playbackDidPause(of: episode, playedUpTo: 700)

        XCTAssertNil(defaults.dictionary(forKey: snapCandidatesKey), "a new pause invalidates the previous pause's candidates immediately")
    }
}

// MARK: - Mock analyzer

private final class MockResumeSnapAnalyzer: ResumeSnapAnalyzing {
    private let requests = Mutex<[(fileURL: URL, targets: [TimeInterval])]>([])
    private let completions = Mutex<[@MainActor @Sendable ([TimeInterval: TimeInterval]) -> Void]>([])

    var requestCount: Int { requests.withLock { $0.count } }
    var lastTargets: [TimeInterval]? { requests.withLock { $0.last?.targets } }
    var lastFileURL: URL? { requests.withLock { $0.last?.fileURL } }

    func completion(at index: Int) -> (@MainActor @Sendable ([TimeInterval: TimeInterval]) -> Void)? {
        completions.withLock { $0.indices.contains(index) ? $0[index] : nil }
    }

    func snapCandidates(for fileURL: URL, targets: [TimeInterval], completion: @escaping @MainActor @Sendable ([TimeInterval: TimeInterval]) -> Void) {
        requests.withLock { $0.append((fileURL: fileURL, targets: targets)) }
        completions.withLock { $0.append(completion) }
    }
}
