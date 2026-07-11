import Foundation
import PocketCastsDataModel
import PocketCastsServer

nonisolated struct OpmlFeed: Equatable, Sendable {
    let title: String
    let url: String
}

nonisolated enum OpmlDocumentError: Error {
    case invalidDocument
}

/// The pure OPML boundary shared by import and export. Keeping XML parsing and
/// generation free of networking and global state makes round-trip coverage
/// deterministic while the existing importer remains responsible for resolving
/// feed URLs through the server.
nonisolated enum OpmlDocument {
    static func xmlString(feeds: [OpmlFeed]) -> String {
        let outlines = feeds.map {
            "<outline type=\"rss\" text=\"\(escapeAttribute($0.title))\" xmlUrl=\"\(escapeAttribute($0.url))\"/>"
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="1.0">
          <head><title>Pocket Casts Feeds</title></head>
          <body>
            <outline text="feeds">
        \(outlines)
            </outline>
          </body>
        </opml>
        """
    }

    static func feedURLs(from data: Data) throws -> [String] {
        let delegate = FeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse(), !delegate.urls.isEmpty else {
            throw OpmlDocumentError.invalidDocument
        }

        return delegate.urls
    }

    private static func escapeAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private final class FeedParser: NSObject, XMLParserDelegate {
        private(set) var urls: [String] = []

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            guard elementName.lowercased() == "outline", let url = attributeDict["xmlUrl"] else { return }

            let trimmedURL = url.trim()
            guard !trimmedURL.isEmpty else { return }

            urls.append(trimmedURL)
        }
    }
}

nonisolated class OpmlImporter: Operation, @unchecked Sendable {
    private var podcastsToAdd = [String]()
    private var pollUuids = [String]()
    private var failedCount = 0

    private let opmlFileUrl: URL
    private let progressWindow: ShiftyLoadingAlert?

    private var initialPodcastCount = 0
    private var importedCount = 0
    private let progressLock = NSLock()

    let importQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 5

        return queue
    }()

    private var parsedUrls = [String]()

    init(opmlFile: URL, progressWindow: ShiftyLoadingAlert? = nil) {
        opmlFileUrl = opmlFile
        self.progressWindow = progressWindow

        super.init()
    }

    override func main() {
        autoreleasepool {
            Analytics.track(.opmlImportStarted)
            // parse OPML file
            guard let data = try? Data(contentsOf: opmlFileUrl),
                  let parsedUrls = try? OpmlDocument.feedURLs(from: data),
                  !parsedUrls.isEmpty else {
                DispatchQueue.main.sync {
                    if let progressWindow = self.progressWindow {
                        progressWindow.hideAlert(false)
                        let controller = SceneHelper.rootViewController()

                        SJUIUtils.showAlert(title: L10n.opmlImportFailedTitle, message: L10n.opmlImportFailedMessage, from: controller)
                    } else {
                        NotificationCenter.postOnMainThread(notification: Constants.Notifications.opmlImportFailed)
                    }

                    Analytics.track(.opmlImportFailed)
                }

                return
            }
            self.parsedUrls = parsedUrls

            initialPodcastCount = parsedUrls.count

            if Settings.localFeedIngestEnabled() {
                // On-device ingest: fetch and parse each feed locally, no server, no polling.
                importPodcastsLocally(urls: parsedUrls)
            } else {
                // send urls to server 100 at a time
                importPodcasts(urls: parsedUrls)

                var amountOfTimesPolled = 0
                while amountOfTimesPolled < 20, !pollUuids.isEmpty {
                    amountOfTimesPolled += 1

                    let pollUuidsToSend = pollUuids
                    pollUuids.removeAll()
                    pollImportPodcasts(pollUuids: pollUuidsToSend)
                    Thread.sleep(forTimeInterval: TimeInterval(amountOfTimesPolled))
                }
            }

            DispatchQueue.main.async {
                if let progressWindow = self.progressWindow {
                    NavigationManager.sharedManager.navigateTo(NavigationManager.podcastListPageKey, data: nil)
                    progressWindow.hideAlert(true)
                }

                NotificationCenter.postOnMainThread(notification: Constants.Notifications.opmlImportCompleted)

                Analytics.track(.opmlImportFinished, properties: ["count": self.initialPodcastCount, "number_parsed": self.initialPodcastCount])
            }
        }
    }

    /// The offline import path: every feed URL goes through the Phase-1 local subscribe
    /// pipeline (`addLocalFeed`), which dedups by feed URL against existing rows of
    /// either refresh regime.
    private func importPodcastsLocally(urls: [String]) {
        for url in urls {
            importQueue.addOperation {
                let addGroup = DispatchGroup()
                addGroup.enter()
                ServerPodcastManager.shared.addLocalFeed(feedURL: url, subscribe: true) { added in
                    let imported = self.updateProgress(failed: !added)

                    DispatchQueue.main.async {
                        guard let progressWindow = self.progressWindow else { return }
                        progressWindow.title = self.progress(imported: imported, total: self.initialPodcastCount)
                    }

                    addGroup.leave()
                }

                // wait for the add operation to return
                _ = addGroup.wait(timeout: .now() + 30.seconds)
            }
        }

        importQueue.waitUntilAllOperationsAreFinished()
    }

    private func importPodcasts(urls: [String]) {
        let serverCallDispatchGroup = DispatchGroup()
        urls.chunked(into: 100).forEach { chunk in
            serverCallDispatchGroup.enter()

            MainServerHandler.shared.sendOpmlChunk(feedUrls: chunk) { response in
                self.processImportPodcastsResponse(response: response, dispatchGroup: serverCallDispatchGroup)
            }

            _ = serverCallDispatchGroup.wait(timeout: .now() + 2.minutes)
        }
    }

    private func pollImportPodcasts(pollUuids: [String]) {
        let serverCallDispatchGroup = DispatchGroup()
        serverCallDispatchGroup.enter()
        MainServerHandler.shared.sendOpmlChunk(pollUuids: pollUuids) { response in
            self.processImportPodcastsResponse(response: response, dispatchGroup: serverCallDispatchGroup)
        }
        _ = serverCallDispatchGroup.wait(timeout: .now() + 2.minutes)
    }

    private func processImportPodcastsResponse(response: ImportOpmlResponse?, dispatchGroup: DispatchGroup) {
        guard let uploadResponse = response, uploadResponse.success() else {
            // since there might be multiple chunks, if this one fails, just go to the next one
            dispatchGroup.leave()
            return
        }

        // since the code below is going to be making more network requests, get this call off the URLSession delegate queue
        DispatchQueue.global().async {
            if let result = uploadResponse.result {
                self.podcastsToAdd = result.uuids ?? []
                self.pollUuids += result.pollUuids ?? []
                self.failedCount += result.failedCount

                self.addAllPendingPodcasts()
                self.podcastsToAdd.removeAll()
            }
            dispatchGroup.leave()
        }
    }

    // MARK: - Add Podcasts

    private func addAllPendingPodcasts() {
        for uuid in podcastsToAdd {
            importQueue.addOperation {
                // check to see if we already have this podcast
                let existingPodcast = DataManager.sharedManager.findPodcast(uuid: uuid, includeUnsubscribed: true)
                if var podcast = existingPodcast {
                    if !podcast.isSubscribed() {
                        podcast.subscribed = 1
                        podcast.syncStatus = SyncStatus.notSynced.rawValue
                        DataManager.sharedManager.save(podcast: podcast)
                    }
                    let imported = self.updateProgress()
                    DispatchQueue.main.async {
                        guard let progressWindow = self.progressWindow else { return }
                        progressWindow.title = self.progress(imported: imported, total: self.initialPodcastCount)
                    }

                    return
                }

                // if we get here we don't have this podcast, so we need to add it
                let addGroup = DispatchGroup()
                addGroup.enter()
                ServerPodcastManager.shared.addFromUuid(podcastUuid: uuid, subscribe: true) { _ in
                    let imported = self.updateProgress()

                    DispatchQueue.main.async {
                        guard let progressWindow = self.progressWindow else { return }
                        progressWindow.title = self.progress(imported: imported, total: self.initialPodcastCount)
                    }

                    addGroup.leave()
                }

                // wait for the add operation to return
                _ = addGroup.wait(timeout: .now() + 30.seconds)
            }
        }

        importQueue.waitUntilAllOperationsAreFinished()
    }

    func progress(imported: Int, total: Int) -> String {
        L10n.opmlImportProgressFormat(imported.localized(), total.localized())
    }

    private func updateProgress(failed: Bool = false) -> Int {
        progressLock.lock()
        defer { progressLock.unlock() }
        importedCount += 1
        if failed { failedCount += 1 }
        return importedCount
    }
}
