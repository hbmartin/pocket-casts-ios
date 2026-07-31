import Foundation
import PocketCastsUtils
import Synchronization

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; retry/completion flags live in the Mutex-guarded PodcastSearchState, the rest is immutable.
class PodcastSearchOperation: Operation, @unchecked Sendable {
    private let completion: @Sendable (PodcastSearchResponse?) -> Void
    private let searchQuery: MainServerHandler.PodcastSearchQuery
    private let urlConnection: URLConnection
    private let state = PodcastSearchState()

    private let dispatchGroup: DispatchGroup = {
        let dispatchGroup = DispatchGroup()

        return dispatchGroup
    }()

    init(searchQuery: MainServerHandler.PodcastSearchQuery, urlConnection: URLConnection, completionHandler: @escaping @Sendable (PodcastSearchResponse?) -> Void) {
        completion = completionHandler
        self.searchQuery = searchQuery
        self.urlConnection = urlConnection
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
        let cancellation = urlConnection.send(request: request) { data, _, error in
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

        let waitResult = dispatchGroup.wait(timeout: .now() + 15.seconds)
        guard waitResult == .success else {
            cancellation.cancel()
            state.setShouldRetry(false)
            state.complete {
                completion(PodcastSearchResponse.failedResponse())
            }
            return false
        }

        return state.shouldRetry()
    }
}

private final class PodcastSearchState: Sendable {
    private struct State {
        var retry = false
        var completed = false
    }

    private let state = Mutex(State())

    func setShouldRetry(_ shouldRetry: Bool) {
        state.withLock { $0.retry = shouldRetry }
    }

    func shouldRetry() -> Bool {
        state.withLock { $0.retry }
    }

    func complete(_ completion: () -> Void) {
        let shouldRun = state.withLock { state in
            if state.completed {
                return false
            }
            state.completed = true
            return true
        }
        guard shouldRun else { return }

        completion()
    }
}
