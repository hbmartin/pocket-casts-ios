import Foundation
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils
import Synchronization

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

/// Shared mutable state used by the operation thread and asynchronous import callbacks.
/// Every access stays behind one lock so late responses after a timeout cannot race with
/// polling or progress updates.
nonisolated final class OpmlImportState: Sendable {
    private struct State {
        var pollUuids = [String]()
        var failedCount = 0
        var importedCount = 0
        var terminalFailure = false
    }

    private let state = Mutex(State())

    @discardableResult
    func recordResponse(pollUuids: [String], failedCount: Int) -> Bool {
        state.withLock { state in
            guard !state.terminalFailure else { return false }
            state.pollUuids += pollUuids
            state.failedCount += failedCount
            return true
        }
    }

    func takePollUuids() -> [String]? {
        state.withLock { state in
            guard !state.terminalFailure, !state.pollUuids.isEmpty else { return nil }
            let uuids = state.pollUuids
            state.pollUuids.removeAll()
            return uuids
        }
    }

    func updateProgress(failed: Bool = false) -> Int {
        state.withLock { state in
            state.importedCount += 1
            if failed { state.failedCount += 1 }
            return state.importedCount
        }
    }

    func recordChunkFailure(feedCount: Int = 1) {
        state.withLock { $0.failedCount += feedCount }
    }

    func markTerminalFailure() {
        state.withLock { state in
            state.terminalFailure = true
            state.pollUuids.removeAll()
        }
    }

    var shouldContinue: Bool {
        state.withLock { !$0.terminalFailure }
    }

    var hasPendingPollUuids: Bool {
        state.withLock { !$0.pollUuids.isEmpty }
    }

    var failureCount: Int {
        state.withLock { $0.failedCount }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; counters live in the lock-guarded OpmlImportState, the rest is confined to main().
nonisolated class OpmlImporter: Operation, @unchecked Sendable {
    private let opmlFileUrl: URL
    private let progressWindow: ShiftyLoadingAlert?
    private let importState = OpmlImportState()

    private var initialPodcastCount = 0

    let importQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 5

        return queue
    }()

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
                finishAsFailure()
                return
            }
            initialPodcastCount = parsedUrls.count

            // send urls to server 100 at a time
            guard importPodcasts(urls: parsedUrls) else {
                finishAsFailure()
                return
            }

            var amountOfTimesPolled = 0
            while amountOfTimesPolled < 20, let pollUuidsToSend = importState.takePollUuids() {
                amountOfTimesPolled += 1

                guard pollImportPodcasts(pollUuids: pollUuidsToSend) else {
                    finishAsFailure()
                    return
                }
                Thread.sleep(forTimeInterval: TimeInterval(amountOfTimesPolled))
            }

            guard !importState.hasPendingPollUuids, importState.shouldContinue else {
                importState.markTerminalFailure()
                finishAsFailure()
                return
            }

            DispatchQueue.main.async {
                if let progressWindow = self.progressWindow {
                    NavigationManager.sharedManager.navigateTo(NavigationManager.podcastListPageKey, data: nil)
                    progressWindow.hideAlert(true)
                }

                NotificationCenter.postOnMainThread(OpmlImportCompleted())

                Analytics.track(.opmlImportFinished, properties: ["count": self.initialPodcastCount, "number_parsed": self.initialPodcastCount])
            }
        }
    }

    private func importPodcasts(urls: [String]) -> Bool {
        let serverCallDispatchGroup = DispatchGroup()
        for chunk in urls.chunked(into: 100) {
            serverCallDispatchGroup.enter()

            MainServerHandler.shared.sendOpmlChunk(feedUrls: chunk) { response in
                self.processImportPodcastsResponse(response: response, feedCount: chunk.count, dispatchGroup: serverCallDispatchGroup)
            }

            guard serverCallDispatchGroup.wait(timeout: .now() + 2.minutes) == .success,
                  importState.shouldContinue else {
                importState.markTerminalFailure()
                return false
            }
        }
        return true
    }

    private func pollImportPodcasts(pollUuids: [String]) -> Bool {
        let serverCallDispatchGroup = DispatchGroup()
        serverCallDispatchGroup.enter()
        MainServerHandler.shared.sendOpmlChunk(pollUuids: pollUuids) { response in
            self.processImportPodcastsResponse(response: response, feedCount: pollUuids.count, dispatchGroup: serverCallDispatchGroup)
        }
        guard serverCallDispatchGroup.wait(timeout: .now() + 2.minutes) == .success,
              importState.shouldContinue else {
            importState.markTerminalFailure()
            return false
        }
        return true
    }

    private func processImportPodcastsResponse(response: ImportOpmlResponse?, feedCount: Int, dispatchGroup: DispatchGroup) {
        guard let uploadResponse = response, uploadResponse.success() else {
            // since there might be multiple chunks, if this one fails, just go to the next one.
            // A chunk carries many feeds, so count each of them as failed to keep the failure
            // total consistent with the per-podcast counting in updateProgress(failed:).
            importState.recordChunkFailure(feedCount: feedCount)
            dispatchGroup.leave()
            return
        }

        // since the code below is going to be making more network requests, get this call off the URLSession delegate queue
        DispatchQueue.global().async {
            if let result = uploadResponse.result {
                if self.importState.recordResponse(
                    pollUuids: result.pollUuids ?? [],
                    failedCount: result.failedCount
                ) {
                    self.addAllPendingPodcasts(podcastUuids: result.uuids ?? [])
                }
            } else {
                // A "successful" envelope with no result payload imported nothing.
                self.importState.recordChunkFailure(feedCount: feedCount)
            }
            dispatchGroup.leave()
        }
    }

    // MARK: - Add Podcasts

    private func addAllPendingPodcasts(podcastUuids: [String]) {
        for uuid in podcastUuids {
            importQueue.addOperation {
                guard self.importState.shouldContinue else { return }
                // check to see if we already have this podcast
                let existingPodcast = DataManager.sharedManager.findPodcast(uuid: uuid, includeUnsubscribed: true)
                if var podcast = existingPodcast {
                    if !podcast.isSubscribed() {
                        guard self.importState.shouldContinue else { return }
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
                guard self.importState.shouldContinue else { return }
                let addGroup = DispatchGroup()
                addGroup.enter()
                ServerPodcastManager.shared.addFromUuid(podcastUuid: uuid, subscribe: true) { _ in
                    guard self.importState.shouldContinue else {
                        addGroup.leave()
                        return
                    }
                    let imported = self.updateProgress()

                    DispatchQueue.main.async {
                        guard let progressWindow = self.progressWindow else { return }
                        progressWindow.title = self.progress(imported: imported, total: self.initialPodcastCount)
                    }

                    addGroup.leave()
                }

                // wait for the add operation to return
                if addGroup.wait(timeout: .now() + 30.seconds) == .timedOut {
                    self.importState.markTerminalFailure()
                }
            }
        }

        importQueue.waitUntilAllOperationsAreFinished()
    }

    func progress(imported: Int, total: Int) -> String {
        L10n.opmlImportProgressFormat(imported.localized(), total.localized())
    }

    private func updateProgress(failed: Bool = false) -> Int {
        importState.updateProgress(failed: failed)
    }

    private func finishAsFailure() {
        DispatchQueue.main.sync {
            if let progressWindow = self.progressWindow {
                progressWindow.hideAlert(false)
                let controller = SceneHelper.rootViewController()
                SJUIUtils.showAlert(
                    title: L10n.opmlImportFailedTitle,
                    message: L10n.opmlImportFailedMessage,
                    from: controller
                )
            } else {
                NotificationCenter.postOnMainThread(OpmlImportFailed())
            }
            Analytics.track(.opmlImportFailed)
        }
    }
}
