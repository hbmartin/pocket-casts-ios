@testable import PocketCastsDataModel
@testable import PocketCastsServer
import GRDB
import XCTest

final class PodcastExistsHelperTests: XCTestCase {
    private let podcastUuid = "podcast-exists-helper-\(UUID().uuidString)"
    private var originalDataManager: DataManager!
    private var dataManager: PodcastLookupDataManager!

    override func setUpWithError() throws {
        try super.setUpWithError()

        originalDataManager = DataManager.sharedManager
        dataManager = try PodcastLookupDataManager()
        DataManager.sharedManager = dataManager
        PodcastExistsHelper.shared.invalidate(uuid: podcastUuid)
    }

    override func tearDownWithError() throws {
        PodcastExistsHelper.shared.invalidate(uuid: podcastUuid)
        DataManager.sharedManager = originalDataManager
        dataManager = nil
        originalDataManager = nil

        try super.tearDownWithError()
    }

    func testPositiveLookupIsCachedUntilInvalidated() {
        let podcast = Podcast()
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
        let podcast = Podcast()
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

private final class PodcastLookupDataManager: DataManager {
    var podcasts: [String: Podcast] = [:]
    var beforeReturningPodcast: ((String) -> Void)?
    private(set) var findPodcastCallCount = 0

    init() throws {
        let dbPath = NSTemporaryDirectory().appending("\(UUID().uuidString).sqlite")
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
