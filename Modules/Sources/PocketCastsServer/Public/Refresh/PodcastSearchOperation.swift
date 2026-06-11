import Foundation
import PocketCastsUtils

class PodcastSearchOperation: Operation, @unchecked Sendable {
    private let completion: @Sendable (PodcastSearchResponse?) -> Void
    private let searchQuery: MainServerHandler.PodcastSearchQuery
    private let state = PodcastSearchState()

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

        dispatchGroup.enter()
        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            defer { self.dispatchGroup.leave() }

            guard let data, error == nil else {
                self.state.setShouldRetry(true)
                return
            }

            do {
                let searchResponse = try JSONDecoder().decode(PodcastSearchResponse.self, from: data)
                if searchResponse.status == "poll" {
                    self.state.setShouldRetry(true)
                } else {
                    self.state.setShouldRetry(false)
                    self.state.complete {
                        self.completion(searchResponse)
                    }
                }
            } catch {
                self.state.setShouldRetry(false)
                self.state.complete {
                    self.completion(PodcastSearchResponse.failedResponse())
                }
            }
        }
        task.resume()

        let waitResult = dispatchGroup.wait(timeout: .now() + 15.seconds)
        guard waitResult == .success else {
            task.cancel()
            state.setShouldRetry(false)
            state.complete {
                completion(PodcastSearchResponse.failedResponse())
            }
            return false
        }

        return state.shouldRetry()
    }
}

private final class PodcastSearchState: @unchecked Sendable {
    private let lock = NSLock()
    private var retry = false
    private var completed = false

    func setShouldRetry(_ shouldRetry: Bool) {
        lock.lock()
        retry = shouldRetry
        lock.unlock()
    }

    func shouldRetry() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return retry
    }

    func complete(_ completion: () -> Void) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()

        completion()
    }
}
