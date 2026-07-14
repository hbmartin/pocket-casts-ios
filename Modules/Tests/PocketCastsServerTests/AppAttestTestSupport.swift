import Foundation
import Synchronization
@testable import PocketCastsServer

/// Scripted stand-in for the DeviceCheck App Attest service so tests can run
/// the full enrollment/assertion lifecycle without Secure Enclave hardware.
final class AppAttestKeyServiceMock: AppAttestKeyService, Sendable {
    struct State {
        var generateKeyCount = 0
        var attestCalls: [(keyId: String, clientDataHash: Data)] = []
        var assertionCalls: [(keyId: String, clientDataHash: Data)] = []
    }

    let supported: Bool
    /// Injected before returning from `generateKey()` so single-flight tests
    /// have a real suspension window while enrollment is in flight.
    let generateKeyDelay: Duration?
    let assertionErrorToThrow: Error?
    let state = Mutex<State>(State())

    init(supported: Bool = true, generateKeyDelay: Duration? = nil, assertionErrorToThrow: Error? = nil) {
        self.supported = supported
        self.generateKeyDelay = generateKeyDelay
        self.assertionErrorToThrow = assertionErrorToThrow
    }

    var isSupported: Bool { supported }

    func generateKey() async throws -> String {
        if let generateKeyDelay {
            try? await Task.sleep(for: generateKeyDelay)
        }
        return state.withLock { state in
            state.generateKeyCount += 1
            return "key-\(state.generateKeyCount)"
        }
    }

    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        state.withLock { $0.attestCalls.append((keyId, clientDataHash)) }
        return Data("attestation-\(keyId)".utf8)
    }

    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        if let assertionErrorToThrow {
            throw assertionErrorToThrow
        }
        state.withLock { $0.assertionCalls.append((keyId, clientDataHash)) }
        return Data("assertion-\(keyId)".utf8)
    }
}

/// In-memory fork backend for the App Attest bootstrap endpoints: serves
/// `GET attest/challenge`, records `POST attest/enroll` bodies (answering with
/// a scripted status sequence), and answers 200 to any other request while
/// recording it (so e.g. a feedback POST can be inspected).
final class AppAttestBackendMock: Sendable {
    struct State {
        var challengeCount = 0
        var enrollBodies: [Data] = []
        /// Consumed front-to-back; the last element repeats once the script runs out.
        var enrollStatuses: [Int]
        var otherRequests: [URLRequest] = []
    }

    let challenge: Data
    let state: Mutex<State>

    init(challenge: Data = Data((1 ... 32).map { UInt8($0) }), enrollStatuses: [Int] = [200]) {
        self.challenge = challenge
        self.state = Mutex(State(enrollStatuses: enrollStatuses))
    }

    var connection: URLConnection {
        URLConnection(mockHandler: handle)
    }

    @Sendable func handle(_ request: URLRequest) throws -> (Data?, URLResponse?) {
        guard let url = request.url else { throw URLError(.badURL) }
        func response(_ status: Int) -> HTTPURLResponse {
            HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        }

        if url.path.hasSuffix("attest/challenge") {
            state.withLock { $0.challengeCount += 1 }
            let body = try JSONSerialization.data(withJSONObject: ["challenge": challenge.base64EncodedString()])
            return (body, response(200))
        }

        if url.path.hasSuffix("attest/enroll") {
            let status = state.withLock { state -> Int in
                state.enrollBodies.append(request.httpBody ?? Data())
                if state.enrollStatuses.count > 1 {
                    return state.enrollStatuses.removeFirst()
                }
                return state.enrollStatuses.first ?? 200
            }
            return (Data(), response(status))
        }

        state.withLock { $0.otherRequests.append(request) }
        return (Data(), response(200))
    }
}
