import Foundation
import PocketCastsUtils

/// A generic request handler to send URLRequests with a completion block
public protocol RequestHandler: Sendable {
    func send(request: URLRequest, completion: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void)
}

extension URLSession: RequestHandler {
    public func send(request: URLRequest, completion: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) {
        let task = dataTask(with: request, completionHandler: completion)
        task.resume()
    }
}

public final class URLConnection: Sendable {

    private let handler: RequestHandler
    private let originPolicy: ServerOriginPolicy

    /// Resolved lazily at send time, never during init: `AppAttestService.shared`'s
    /// own initializer constructs a default `URLConnection`, so evaluating `.shared`
    /// as an init default argument would re-enter that static initialization and
    /// deadlock the first thread to construct either singleton.
    private let injectedAppAttestService: AppAttestService?
    private var appAttestService: AppAttestService { injectedAppAttestService ?? .shared }

    public init(
        handler: RequestHandler,
        originPolicy: ServerOriginPolicy = .shared,
        appAttestService: AppAttestService? = nil
    ) {
        self.handler = handler
        self.originPolicy = originPolicy
        self.injectedAppAttestService = appAttestService
    }

    public func sendSynchronousRequest(with request: URLRequest) throws -> (Data?, URLResponse?) {
        // The semaphore establishes the happens-before edge for the boxed result.
        let result = UncheckedSendableBox<(Data?, URLResponse?, Error?)>((nil, nil, nil))
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            do {
                let response = try await send(request: request)
                result.value = (response.0, response.1, nil)
            } catch {
                result.value = (nil, nil, error)
            }
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .distantFuture)
        let (data, response, error) = result.value
        if let error {
            throw error
        }
        return (data, response)
    }

    public func send(request: URLRequest, completion: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) {
        Task {
            do {
                let (data, response) = try await send(request: request)
                completion(data, response, nil)
            } catch {
                completion(nil, nil, error)
            }
        }
    }

    public func send(request: URLRequest) async throws -> (Data?, URLResponse?) {
        guard originPolicy.isNetworkAllowed else {
            throw ServerOriginError.networkBlocked(originPolicy.blockingMessage ?? "Server networking is disabled.")
        }

        var preparedRequest = request
        if AppAttestRoutePolicy.isSelfHosted(request, origin: originPolicy.origin),
           preparedRequest.value(forHTTPHeaderField: ServerConstants.HttpHeaders.installationID) == nil,
           let installationID = ServerConfig.shared.syncDelegate?.uniqueAppId(), !installationID.isEmpty {
            preparedRequest.setValue(installationID, forHTTPHeaderField: ServerConstants.HttpHeaders.installationID)
        }

        if AppAttestRoutePolicy.requiresAttestation(preparedRequest, origin: originPolicy.origin) {
            return try await appAttestService.send(request: preparedRequest, using: self)
        }

        return try await sendRaw(request: preparedRequest)
    }

    /// Bypasses policy/interceptors for the App Attest bootstrap and for the
    /// transport's already-signed attempt. Not public outside this module.
    func sendRaw(request: URLRequest) async throws -> (Data?, URLResponse?) {
        try await withCheckedThrowingContinuation { continuation in
            handler.send(request: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (data, response))
                }
            }
        }
    }
}
