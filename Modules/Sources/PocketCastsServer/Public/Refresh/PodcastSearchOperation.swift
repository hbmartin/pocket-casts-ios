import Foundation
import PocketCastsUtils

class PodcastSearchOperation: Operation, @unchecked Sendable {
    private let completion: @Sendable (PodcastSearchResponse?) -> Void
    private let searchQuery: MainServerHandler.PodcastSearchQuery

    private let dispatchGroup: DispatchGroup = {
        let dispatchGroup = DispatchGroup()

        return dispatchGroup
    }()

    init(searchQuery: MainServerHandler.PodcastSearchQuery, completionHandler: @escaping @Sendable (PodcastSearchResponse?) -> Void) {
        completion = completionHandler
        self.searchQuery = searchQuery
        super.init()
    }

    // This method calls a pollable API that is defined as needing to be called like this by the server team:
    // call first time, if status == "poll"
    // Wait 2 seconds then call again
    // Wait 2 seconds then call
    // Wait 5 seconds then call
    // Wait 5 seconds then call
    // Wait 5 seconds then call
    // Wait 5 seconds then call
    // Wait 10 seconds then call
    // give up
    override func main() {
        autoreleasepool {
            var pollCount = 0
            while true {
                let shouldRetry = performSearch()
                if !shouldRetry { break }

                pollCount += 1
                let backOffTime = pollCount.pollWaitingTime
                if backOffTime < 0 {
                    completion(PodcastSearchResponse.failedResponse())
                    break
                }

                Thread.sleep(forTimeInterval: backOffTime)
            }
        }
    }

    private func performSearch() -> Bool {
        let url = ServerHelper.asUrl(ServerConstants.Urls.main() + "podcasts/search")
        guard let request = ServerHelper.createJsonRequest(url: url, params: searchQuery, timeout: 10, cachePolicy: .reloadIgnoringCacheData) else {
            completion(PodcastSearchResponse.failedResponse())

            return false
        }

        // The dispatch-group wait establishes the happens-before edge for the boxed flag.
        let shouldRetry = UncheckedSendableBox(false)
        dispatchGroup.enter()
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data, error == nil else {
                shouldRetry.value = true
                self.dispatchGroup.leave()
                return
            }

            do {
                let searchResponse = try JSONDecoder().decode(PodcastSearchResponse.self, from: data)
                if searchResponse.status == "poll" {
                    shouldRetry.value = true
                } else {
                    shouldRetry.value = false
                    self.completion(searchResponse)
                }
            } catch {
                self.completion(PodcastSearchResponse.failedResponse())
            }

            self.dispatchGroup.leave()
        }.resume()
        _ = dispatchGroup.wait(timeout: .now() + 15.seconds)

        return shouldRetry.value
    }
}
