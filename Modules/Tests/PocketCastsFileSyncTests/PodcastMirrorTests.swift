import GRDB
import XCTest
@testable import PocketCastsDataModel
@testable import PocketCastsFileSync

final class PodcastMirrorTests: XCTestCase {
    private var testDirectory: URL!
    private var folder: InMemorySyncFolder!

    override func setUp() {
        super.setUp()
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("podcast-mirror-tests")
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        folder = InMemorySyncFolder()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testDirectory)
        testDirectory = nil
        folder = nil
        super.tearDown()
    }

    private func makeDataManager(name: String) throws -> DataManager {
        var config = Configuration()
        config.busyMode = .timeout(10)
        let pool = try DatabasePool(path: testDirectory.appendingPathComponent(name).path, configuration: config)
        return DataManager(dbQueue: GRDBQueue(dbPool: pool))
    }

    private func seedEpisode(on dataManager: DataManager, uuid: String, podcastUuid: String, downloaded: Bool) -> Episode {
        var podcast = dataManager.findPodcast(uuid: podcastUuid, includeUnsubscribed: true) ?? {
            var new = Podcast()
            new.uuid = podcastUuid
            new.addedDate = Date()
            new.subscribed = 1
            return dataManager.save(podcast: new)
        }()

        var episode = Episode()
        episode.uuid = uuid
        episode.addedDate = Date()
        episode.title = uuid
        episode.podcastUuid = podcast.uuid
        episode.podcast_id = podcast.id
        episode.episodeStatus = (downloaded ? DownloadStatus.downloaded : DownloadStatus.notDownloaded).rawValue
        dataManager.save(episode: episode)
        return episode
    }

    /// Local cache layout for a fake device: one directory per device name.
    private func pathResolver(deviceName: String) -> @Sendable (Episode) -> String {
        let base = testDirectory.appendingPathComponent("cache-\(deviceName)")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return { episode in
            base.appendingPathComponent("\(episode.uuid).mp3").path
        }
    }

    func testFormatRoundTripsEntryPaths() {
        let path = PodcastMirrorFormat.relativePath(podcastUuid: "pod-1", episodeUuid: "ep-1", fileExtension: "m4a")
        XCTAssertEqual(path, "Podcast Mirrors/pod-1/ep-1.m4a")

        let entry = PodcastMirrorFormat.entry(from: FolderEntry(
            relativePath: path, sizeBytes: 42, mtimeMs: 0, isDirectory: false, isPlaceholder: false))
        XCTAssertEqual(entry?.podcastUuid, "pod-1")
        XCTAssertEqual(entry?.episodeUuid, "ep-1")
        XCTAssertEqual(entry?.sizeBytes, 42)

        // wrong shapes are ignored
        XCTAssertNil(PodcastMirrorFormat.entry(from: FolderEntry(
            relativePath: "Uploads/file.mp3", sizeBytes: 1, mtimeMs: 0, isDirectory: false, isPlaceholder: false)))
        XCTAssertNil(PodcastMirrorFormat.entry(from: FolderEntry(
            relativePath: "Podcast Mirrors/pod-1", sizeBytes: 0, mtimeMs: 0, isDirectory: true, isPlaceholder: false)))
        XCTAssertNil(PodcastMirrorFormat.entry(from: FolderEntry(
            relativePath: "Podcast Mirrors/pod-1/nested/ep.mp3", sizeBytes: 1, mtimeMs: 0, isDirectory: false, isPlaceholder: false)))
    }

    func testMirrorKeepsSanitizedDestinationsInsideMirrorDirectory() async throws {
        let cases = [
            (podcastUuid: "pod-1", episodeUuid: "ep-1", expectedPath: "Podcast Mirrors/pod-1/ep-1.mp3"),
            (podcastUuid: "../outside", episodeUuid: "../episode", expectedPath: "Podcast Mirrors/___outside/___episode.mp3"),
            (podcastUuid: "pod/cast", episodeUuid: "episode/name", expectedPath: "Podcast Mirrors/pod_cast/episode_name.mp3"),
            (podcastUuid: "pod.cast:?", episodeUuid: "episode?#", expectedPath: "Podcast Mirrors/pod_cast__/episode__.mp3"),
            (podcastUuid: "播客-ü", episodeUuid: "章節-é", expectedPath: "Podcast Mirrors/播客-ü/章節-é.mp3")
        ]
        let dataManager = try makeDataManager(name: "sanitized-paths.sqlite3")

        for (index, testCase) in cases.enumerated() {
            let episode = seedEpisode(
                on: dataManager,
                uuid: testCase.episodeUuid,
                podcastUuid: testCase.podcastUuid,
                downloaded: true
            )
            let localURL = testDirectory.appendingPathComponent("audio-\(index).mp3")
            try Data("audio-\(index)".utf8).write(to: localURL)
            let materializer = PodcastMirrorMaterializer(
                folder: folder,
                dataManager: dataManager,
                localPathResolver: { _ in localURL.path }
            )

            XCTAssertTrue(try await materializer.mirror(episodeUuid: episode.uuid))
        }

        let createdPaths = await folder.createdDirectoryPaths()
        let copiedPaths = await folder.storedFilePaths()
        XCTAssertEqual(Set(copiedPaths), Set(cases.map(\.expectedPath)))
        XCTAssertEqual(createdPaths.count, cases.count)

        let syncRoot = URL(fileURLWithPath: "/sync-root", isDirectory: true)
        let mirrorRoot = syncRoot
            .appendingPathComponent(FileSyncFormat.podcastMirrorsDirectory, isDirectory: true)
            .standardizedFileURL
        for path in createdPaths + copiedPaths {
            let resolved = syncRoot.appendingPathComponent(path).standardizedFileURL
            XCTAssertTrue(
                resolved.path.hasPrefix(mirrorRoot.path + "/"),
                "Destination escaped Podcast Mirrors: \(path) resolves to \(resolved.path)"
            )
        }
    }

    func testDownloadOnDeviceAMaterializesOnDeviceB() async throws {
        let audio = Data("mirrored audio bytes".utf8)

        // Device A: episode downloaded, audio in its local cache.
        let deviceA = try makeDataManager(name: "deviceA.sqlite3")
        let resolverA = pathResolver(deviceName: "A")
        let episodeA = seedEpisode(on: deviceA, uuid: "ep-1", podcastUuid: "pod-1", downloaded: true)
        try audio.write(to: URL(fileURLWithPath: resolverA(episodeA)))

        let scannerA = PodcastMirrorScanner(
            folder: folder, dataManager: deviceA,
            materializer: PodcastMirrorMaterializer(folder: folder, dataManager: deviceA, localPathResolver: resolverA))
        let outResult = try await scannerA.scan(materializeIn: false)
        XCTAssertEqual(outResult.mirrored, 1)
        let mirroredData = await folder.contents(of: "Podcast Mirrors/pod-1/ep-1.mp3")
        XCTAssertEqual(mirroredData, audio)

        // Device B: same episode row, no audio yet.
        let deviceB = try makeDataManager(name: "deviceB.sqlite3")
        let resolverB = pathResolver(deviceName: "B")
        let episodeB = seedEpisode(on: deviceB, uuid: "ep-1", podcastUuid: "pod-1", downloaded: false)

        let scannerB = PodcastMirrorScanner(
            folder: folder, dataManager: deviceB,
            materializer: PodcastMirrorMaterializer(folder: folder, dataManager: deviceB, localPathResolver: resolverB))
        let inResult = try await scannerB.scan(materializeIn: true)
        XCTAssertEqual(inResult.materialized, 1)

        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: resolverB(episodeB))), audio)
        XCTAssertEqual(deviceB.findEpisode(uuid: "ep-1")?.episodeStatus, DownloadStatus.downloaded.rawValue)
    }

    func testMaterializeInRespectsSizeCapAndSkipsUnknownEpisodes() async throws {
        let deviceB = try makeDataManager(name: "deviceB.sqlite3")
        let resolverB = pathResolver(deviceName: "B")

        _ = seedEpisode(on: deviceB, uuid: "ep-known", podcastUuid: "pod-1", downloaded: false)
        try await folder.coordinatedWrite("Podcast Mirrors/pod-1/ep-known.mp3", data: Data(count: 2048))
        // a mirror for an episode this device has no row for must be left alone
        try await folder.coordinatedWrite("Podcast Mirrors/pod-1/ep-unknown.mp3", data: Data(count: 16))

        let scanner = PodcastMirrorScanner(
            folder: folder, dataManager: deviceB,
            materializer: PodcastMirrorMaterializer(folder: folder, dataManager: deviceB, localPathResolver: resolverB))

        // cap below the file size: nothing is pulled, and the skip is reported
        let capped = try await scanner.scan(materializeIn: true, maxMaterializeBytes: 1024)
        XCTAssertEqual(capped.materialized, 0)
        XCTAssertEqual(capped.skippedBySizeCap, 1)

        // no cap: only the known episode materializes
        let uncapped = try await scanner.scan(materializeIn: true)
        XCTAssertEqual(uncapped.materialized, 1)
        XCTAssertEqual(deviceB.findEpisode(uuid: "ep-known")?.episodeStatus, DownloadStatus.downloaded.rawValue)
    }
}
