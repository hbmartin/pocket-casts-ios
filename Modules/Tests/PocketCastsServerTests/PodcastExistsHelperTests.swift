@testable import PocketCastsDataModel
@testable import PocketCastsServer
import GRDB
import XCTest

final class PodcastExistsHelperTests: XCTestCase {
    private let podcastUuid = "podcast-exists-helper-\(UUID().uuidString)"
    private var originalDataManager: DataManager!
    private var dataManager: PodcastLookupDataManager!
    private var temporaryDatabaseDirectory: URL?

    override func setUpWithError() throws {
        try super.setUpWithError()

        originalDataManager = DataManager.sharedManager
        let temporaryDatabaseDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDatabaseDirectory, withIntermediateDirectories: true)
        self.temporaryDatabaseDirectory = temporaryDatabaseDirectory
        dataManager = try PodcastLookupDataManager(dbPath: temporaryDatabaseDirectory.appendingPathComponent("database.sqlite").path)
        DataManager.sharedManager = dataManager
        PodcastExistsHelper.shared.invalidate(uuid: podcastUuid)
    }

    override func tearDownWithError() throws {
        PodcastExistsHelper.shared.invalidate(uuid: podcastUuid)
        DataManager.sharedManager = originalDataManager
        dataManager = nil
        originalDataManager = nil
        if let temporaryDatabaseDirectory {
            try? FileManager.default.removeItem(at: temporaryDatabaseDirectory)
        }
        temporaryDatabaseDirectory = nil

        try super.tearDownWithError()
    }

    func testPositiveLookupIsCachedUntilInvalidated() {
        var podcast = Podcast()
        podcast.uuid = podcastUuid
        dataManager.podcasts[podcastUuid] = podcast

        XCTAssertTrue(PodcastExistsHelper.shared.exists(uuid: podcastUuid))
        XCTAssertEqual(dataManager.findPodcastCallCount, 1)

        dataManager.podcasts[podcastUuid] = nil

        XCTAssertTrue(PodcastExistsHelper.shared.exists(uuid: podcastUuid))
        XCTAssertEqual(dataManager.findPodcastCallCount, 1)

        PodcastExistsHelper.shared.invalidate(uuid: podcastUuid)

        XCTAssertFalse(PodcastExistsHelper.shared.exists(uuid: podcastUuid))
        XCTAssertEqual(dataManager.findPodcastCallCount, 2)
    }

    func testLookupDoesNotCacheResultWhenInvalidatedDuringDatabaseLookup() {
        var podcast = Podcast()
        podcast.uuid = podcastUuid
        dataManager.podcasts[podcastUuid] = podcast
        dataManager.beforeReturningPodcast = { [weak dataManager] uuid in
            PodcastExistsHelper.shared.invalidate(uuid: uuid)
            dataManager?.podcasts[uuid] = nil
        }

        XCTAssertTrue(PodcastExistsHelper.shared.exists(uuid: podcastUuid))
        XCTAssertEqual(dataManager.findPodcastCallCount, 1)

        dataManager.beforeReturningPodcast = nil

        XCTAssertFalse(PodcastExistsHelper.shared.exists(uuid: podcastUuid))
        XCTAssertEqual(dataManager.findPodcastCallCount, 2)
    }
}

// @unchecked Sendable: restates DataManager's conformance, as Swift requires of subclasses; test-only stub state.
private final class PodcastLookupDataManager: DataManager, @unchecked Sendable {
    var podcasts: [String: Podcast] = [:]
    var beforeReturningPodcast: ((String) -> Void)?
    private(set) var findPodcastCallCount = 0

    init(dbPath: String = NSTemporaryDirectory().appending("\(UUID().uuidString).sqlite")) throws {
        let pool = try DatabasePool(path: dbPath)
        super.init(dbQueue: GRDBQueue(dbPool: pool, logger: DataManager.logger))
    }

    override public func findPodcast(uuid: String, includeUnsubscribed: Bool = false) -> Podcast? {
        findPodcastCallCount += 1
        let podcast = podcasts[uuid]
        beforeReturningPodcast?(uuid)
        return podcast
    }
}
