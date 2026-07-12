import Foundation
import PocketCastsServer
import PocketCastsUtils

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; stored properties are immutable and the async lookup is joined via dispatchGroup.
nonisolated class SharedItemImporter: Operation, @unchecked Sendable {
    private let urlToImport: String
    private let completion: (IncomingShareItem?) -> Void

    private let dispatchGroup: DispatchGroup = {
        let dispatchGroup = DispatchGroup()

        return dispatchGroup
    }()

    init(strippedUrl: String, completion: @escaping (IncomingShareItem?) -> Void) {
        urlToImport = strippedUrl
        self.completion = completion
    }

    override func main() {
        autoreleasepool {
            dispatchGroup.enter()
            MainServerHandler.shared.lookupShareLink(sharePath: urlToImport) { [weak self] listResponse in
                guard let listResponse, listResponse.success() else {
                    self?.sendResponse()
                    return
                }

                let incomingItem = IncomingShareItem()
                if let podcast = listResponse.result?.podcast {
                    incomingItem.podcastHeader = PodcastHeader(sharedPodcast: podcast)
                }
                incomingItem.fromTime = listResponse.result?.time
                if let episode = listResponse.result?.episode {
                    incomingItem.episodeHeader = EpisodeHeader(refreshEpisode: episode)
                }

                self?.sendResponse(item: incomingItem)
            }

            _ = dispatchGroup.wait(timeout: .now() + 30.seconds)
        }
    }

    private func sendResponse(item: IncomingShareItem? = nil) {
        // The item is freshly parsed and handed over wholesale to the main-thread completion
        let boxed = PocketCastsUtils.UncheckedSendable(item)
        DispatchQueue.main.sync { [weak self] in
            self?.completion(boxed.value)
        }
        dispatchGroup.leave()
    }
}
