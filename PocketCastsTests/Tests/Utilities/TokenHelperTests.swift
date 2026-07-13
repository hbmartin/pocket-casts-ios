import Foundation
import XCTest
@testable import PocketCastsUtils
@testable import PocketCastsServer

fileprivate extension URL {
    static var userLogin: URL {
        return ServerHelper.asUrl(ServerConstants.Urls.api() + "user/login")
    }
    static var userUpdate: URL {
        return ServerHelper.asUrl(ServerConstants.Urls.main() + "user/update")
    }
}

/// A tiny lock-guarded box so mock handlers can record state across threads.
// @unchecked Sendable: all access to `value` goes through the NSLock below.
private final class LockedBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value {
        lock.withLock { storedValue }
    }

    func mutate(_ transform: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        transform(&storedValue)
    }
}

class TokenHelperTests: XCTestCase {
    private var previousKeychainStore: KeychainStoring!
    private let flagMock = FeatureFlagMock()

    override func setUp() {
        super.setUp()
        // The credentials these tests store via ServerSettings are incidental — use an
        // in-memory keychain so the tests don't depend on real keychain state.
        previousKeychainStore = KeychainHelper.store
        KeychainHelper.store = InMemoryKeychainStore()
        ServerSettings.setTokenExpiryDate(nil)
        ServerSettings.accountAuthMethod = nil
        URLProtocol.registerClass(TokenGrantURLProtocol.self)
        TokenGrantURLProtocol.resetCount()
    }

    override func tearDown() {
        TokenGrantURLProtocol.stub = nil
        URLProtocol.unregisterClass(TokenGrantURLProtocol.self)
        ServerSettings.setTokenExpiryDate(nil)
        ServerSettings.accountAuthMethod = nil
        flagMock.reset()
        KeychainHelper.store = previousKeychainStore
        super.tearDown()
    }

    // MARK: - Helpers

    private func loginResponseData(token: String = "1234", email: String = "test@test.com") throws -> Data {
        var object = Api_UserLoginResponse()
        object.token = token
        object.uuid = UUID().uuidString
        object.email = email
        return try object.serializedData()
    }

    private func tokenLoginResponseData(accessToken: String, refreshToken: String, expiresIn: Int32 = 0) throws -> Data {
        var object = Api_TokenLoginResponse()
        object.accessToken = accessToken
        object.refreshToken = refreshToken
        object.expiresIn = expiresIn
        object.uuid = UUID().uuidString
        object.email = "test@test.com"
        return try object.serializedData()
    }

    /// Runs the blocking `acquireToken()` off the test thread and returns its result.
    private func acquireTokenOnBackgroundQueue(_ tokenHelper: TokenHelper, timeout: TimeInterval = 15) -> String? {
        let done = XCTestExpectation(description: "acquireToken finished")
        let result = LockedBox<String?>(nil)
        DispatchQueue.global().async {
            let token = tokenHelper.acquireToken()
            result.mutate { $0 = token }
            done.fulfill()
        }
        wait(for: [done], timeout: timeout)
        return result.value
    }

    // MARK: - Password acquisition

    /// Tests the acquirePasswordToken function
    func testAcquirePasswordToken() async throws {
        ServerSettings.setSyncingEmail(email: "test@test.com")
        ServerSettings.saveSyncingPassword("1234")

        let responseData = try loginResponseData()
        let tokenHelper = TokenHelper(urlConnection: URLConnection { request in
            if request.url == URL.userLogin {
                let response = HTTPURLResponse(url: .userLogin, statusCode: 200, httpVersion: nil, headerFields: nil)
                return (responseData, response)
            } else {
                throw NSError(domain: "TokenHelperTests", code: 1)
            }
        })

        let response = try await tokenHelper.acquirePasswordToken()
        XCTAssertEqual(response?.token, "1234")
        XCTAssertEqual(response?.email, "test@test.com")
        XCTAssertNotNil(response?.uuid, "Should receive UUID")
    }

    /// Tests the acquireAsyncToken function
    func testAcquireAsyncToken() throws {
        ServerSettings.setSyncingEmail(email: "test@test.com")
        ServerSettings.saveSyncingPassword("1234")

        let responseData = try loginResponseData()
        let tokenHelper = TokenHelper(urlConnection: URLConnection { request in
            if request.url == URL.userLogin {
                let response = HTTPURLResponse(url: .userLogin, statusCode: 200, httpVersion: nil, headerFields: nil)
                return (responseData, response)
            } else {
                throw NSError(domain: "TokenHelperTests", code: 1)
            }
        })

        let expectation = XCTestExpectation(description: "Waiting on asyncAcquireToken to complete")
        tokenHelper.asyncAcquireToken { result in
            switch result {
            case .success(let response):
                XCTAssertEqual(response?.token, "1234")
                XCTAssertEqual(response?.email, "test@test.com")
                XCTAssertNotNil(response?.uuid, "Should receive UUID")
            case .failure(let error):
                XCTFail("Failed async acquire with error: \(error)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 15)
    }

    func testCallSecureURL() throws {
        ServerSettings.setSyncingEmail(email: "test@test.com")
        ServerSettings.saveSyncingPassword("1234")

        let responseData = try loginResponseData()
        let tokenHelper = TokenHelper(urlConnection: URLConnection { request in
            switch request.url {
            case URL.userLogin:
                let response = HTTPURLResponse(url: .userLogin, statusCode: 200, httpVersion: nil, headerFields: nil)
                return (responseData, response)
            case URL.userUpdate:
                let response = HTTPURLResponse(url: .userUpdate, statusCode: 200, httpVersion: nil, headerFields: nil)
                // Any data will do here, just to see if it makes it through
                let data = "Test".data(using: .utf8)
                return (data, response)
            default:
                throw NSError(domain: "TokenHelperTests", code: 1)
            }
        })

        let expectation = XCTestExpectation(description: "Waiting on callSecureUrl to complete")
        tokenHelper.callSecureUrl(request: URLRequest(url: .userUpdate)) { response, data, error in
            if let error {
                XCTFail("Failed async acquire with error: \(error)")
            } else {
                XCTAssertNotNil(response, "Should have received response")
                XCTAssertNotNil(data, "Should have received data")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 15)
    }

    // MARK: - C.0-1: empty-refresh-token clobber guard

    func testPasswordLoginDoesNotClobberStoredRefreshToken() throws {
        ServerSettings.setSyncingEmail(email: "test@test.com")
        ServerSettings.saveSyncingPassword("1234")
        ServerSettings.setRefreshToken("keep-me")

        let responseData = try loginResponseData(token: "fresh-token")
        let tokenHelper = TokenHelper(urlConnection: URLConnection { request in
            guard request.url == URL.userLogin else { throw NSError(domain: "TokenHelperTests", code: 1) }
            let response = HTTPURLResponse(url: .userLogin, statusCode: 200, httpVersion: nil, headerFields: nil)
            return (responseData, response)
        })

        let token = acquireTokenOnBackgroundQueue(tokenHelper)

        XCTAssertEqual(token, "fresh-token")
        XCTAssertEqual(ServerSettings.syncingV2Token, "fresh-token")
        XCTAssertEqual(try ServerSettings.refreshToken(), "keep-me", "A login response without a refresh token must not clobber the stored one")
    }

    func testEmptyRefreshTokenFromRefreshGrantIsNotPersisted() throws {
        // No stored password, so acquisition falls through to the refresh grant, which
        // goes out via URLSession.shared and is intercepted by TokenGrantURLProtocol.
        ServerSettings.setSyncingEmail(email: "test@test.com")
        ServerSettings.setRefreshToken("keep-me")

        let grantBody = try tokenLoginResponseData(accessToken: "fresh-token", refreshToken: "")
        TokenGrantURLProtocol.stub = { _ in
            TokenGrantURLProtocol.StubResponse(statusCode: 200, body: grantBody)
        }

        let tokenHelper = TokenHelper(urlConnection: URLConnection { _ in
            throw NSError(domain: "TokenHelperTests", code: 1)
        })

        let token = acquireTokenOnBackgroundQueue(tokenHelper)

        XCTAssertEqual(token, "fresh-token")
        XCTAssertEqual(ServerSettings.syncingV2Token, "fresh-token")
        XCTAssertEqual(try ServerSettings.refreshToken(), "keep-me", "An empty refresh token in the grant response must not clobber the stored one")
    }

    func testRefreshGrantPersistsRotatedRefreshTokenAndExpiry() throws {
        ServerSettings.setSyncingEmail(email: "test@test.com")
        ServerSettings.setRefreshToken("original-refresh")

        let grantBody = try tokenLoginResponseData(accessToken: "fresh-token", refreshToken: "rotated-refresh", expiresIn: 3600)
        TokenGrantURLProtocol.stub = { _ in
            TokenGrantURLProtocol.StubResponse(statusCode: 200, body: grantBody)
        }

        let tokenHelper = TokenHelper(urlConnection: URLConnection { _ in
            throw NSError(domain: "TokenHelperTests", code: 1)
        })

        let token = acquireTokenOnBackgroundQueue(tokenHelper)

        XCTAssertEqual(token, "fresh-token")
        XCTAssertEqual(try ServerSettings.refreshToken(), "rotated-refresh")

        let expiry = try XCTUnwrap(ServerSettings.tokenExpiryDate(), "expires_in should persist an expiry hint")
        // 3600s TTL minus the 5 minute skew.
        XCTAssertEqual(expiry.timeIntervalSinceNow, 3300, accuracy: 30)
    }

    // MARK: - C.0-3: single-flight acquisition

    func testConcurrentAcquireTokenMakesSingleLoginRequest() throws {
        ServerSettings.setSyncingEmail(email: "test@test.com")
        ServerSettings.saveSyncingPassword("1234")

        let loginRequestCount = LockedBox(0)
        let releaseLogin = DispatchSemaphore(value: 0)
        let responseData = try loginResponseData()

        let tokenHelper = TokenHelper(urlConnection: URLConnection { request in
            guard request.url == URL.userLogin else { throw NSError(domain: "TokenHelperTests", code: 1) }
            loginRequestCount.mutate { $0 += 1 }
            // Hold the in-flight window open until every acquirer has queued up.
            releaseLogin.wait()
            let response = HTTPURLResponse(url: .userLogin, statusCode: 200, httpVersion: nil, headerFields: nil)
            return (responseData, response)
        })

        let acquirerCount = 8
        let allDone = XCTestExpectation(description: "All acquirers finished")
        allDone.expectedFulfillmentCount = acquirerCount
        let tokens = LockedBox([String?]())

        for _ in 0 ..< acquirerCount {
            DispatchQueue.global().async {
                let token = tokenHelper.acquireToken()
                tokens.mutate { $0.append(token) }
                allDone.fulfill()
            }
        }

        // Give every acquirer time to reach the single-flight gate, then let the one
        // in-flight login proceed.
        Thread.sleep(forTimeInterval: 0.5)
        releaseLogin.signal()

        wait(for: [allDone], timeout: 15)

        XCTAssertEqual(loginRequestCount.value, 1, "Concurrent acquirers must share a single login request")
        XCTAssertEqual(tokens.value.count, acquirerCount)
        XCTAssertTrue(tokens.value.allSatisfy { $0 == "1234" }, "Every caller should receive the shared token")
    }

    // MARK: - C.0-2: expiry hint

    func testExpiredStoredTokenTriggersProactiveRefresh() throws {
        ServerSettings.setSyncingEmail(email: "test@test.com")
        ServerSettings.saveSyncingPassword("1234")
        ServerSettings.syncingV2Token = "stale-token"
        ServerSettings.setTokenExpiryDate(Date(timeIntervalSinceNow: -60))

        let responseData = try loginResponseData(token: "fresh-token")
        let authorizationHeader = LockedBox<String?>(nil)

        let tokenHelper = TokenHelper(urlConnection: URLConnection { request in
            switch request.url {
            case URL.userLogin:
                let response = HTTPURLResponse(url: .userLogin, statusCode: 200, httpVersion: nil, headerFields: nil)
                return (responseData, response)
            case URL.userUpdate:
                let header = request.value(forHTTPHeaderField: "Authorization")
                authorizationHeader.mutate { $0 = header }
                let response = HTTPURLResponse(url: .userUpdate, statusCode: 200, httpVersion: nil, headerFields: nil)
                return ("Test".data(using: .utf8), response)
            default:
                throw NSError(domain: "TokenHelperTests", code: 1)
            }
        })

        let expectation = XCTestExpectation(description: "Secure call finished")
        tokenHelper.callSecureUrl(request: URLRequest(url: .userUpdate)) { response, _, _ in
            XCTAssertEqual(response?.statusCode, 200)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 15)

        XCTAssertEqual(authorizationHeader.value, "Bearer fresh-token", "An expired stored token must be refreshed proactively before the call")
    }

    func testStoredTokenWithoutExpiryHintIsUsedAsIs() {
        ServerSettings.setSyncingEmail(email: "test@test.com")
        ServerSettings.saveSyncingPassword("1234")
        ServerSettings.syncingV2Token = "stored-token"

        let loginRequestCount = LockedBox(0)
        let authorizationHeader = LockedBox<String?>(nil)

        let tokenHelper = TokenHelper(urlConnection: URLConnection { request in
            switch request.url {
            case URL.userLogin:
                loginRequestCount.mutate { $0 += 1 }
                throw NSError(domain: "TokenHelperTests", code: 1)
            case URL.userUpdate:
                let header = request.value(forHTTPHeaderField: "Authorization")
                authorizationHeader.mutate { $0 = header }
                let response = HTTPURLResponse(url: .userUpdate, statusCode: 200, httpVersion: nil, headerFields: nil)
                return ("Test".data(using: .utf8), response)
            default:
                throw NSError(domain: "TokenHelperTests", code: 1)
            }
        })

        let expectation = XCTestExpectation(description: "Secure call finished")
        tokenHelper.callSecureUrl(request: URLRequest(url: .userUpdate)) { response, _, _ in
            XCTAssertEqual(response?.statusCode, 200)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 15)

        XCTAssertEqual(loginRequestCount.value, 0, "A stored token without an expiry hint must be used as-is (absent expires_in ⇒ today's behavior)")
        XCTAssertEqual(authorizationHeader.value, "Bearer stored-token")
    }

    // MARK: - C.0-4: 429 Retry-After

    func test429OnSecureCallRetriesOnceAfterRetryAfter() {
        // Signed out, so the secure call goes straight through without token logic.
        let requestCount = LockedBox(0)

        let tokenHelper = TokenHelper(urlConnection: URLConnection { request in
            guard request.url == URL.userUpdate else { throw NSError(domain: "TokenHelperTests", code: 1) }
            var count = 0
            requestCount.mutate { $0 += 1; count = $0 }
            if count == 1 {
                let response = HTTPURLResponse(url: .userUpdate, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "0"])
                return (nil, response)
            }
            let response = HTTPURLResponse(url: .userUpdate, statusCode: 200, httpVersion: nil, headerFields: nil)
            return ("Test".data(using: .utf8), response)
        })

        let expectation = XCTestExpectation(description: "Secure call finished")
        tokenHelper.callSecureUrl(request: URLRequest(url: .userUpdate)) { response, data, _ in
            XCTAssertEqual(response?.statusCode, 200, "The rate-limited call should succeed on its single retry")
            XCTAssertNotNil(data)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 15)

        XCTAssertEqual(requestCount.value, 2)
    }

    func test429OnSecureCallDoesNotLoop() {
        let requestCount = LockedBox(0)

        let tokenHelper = TokenHelper(urlConnection: URLConnection { request in
            guard request.url == URL.userUpdate else { throw NSError(domain: "TokenHelperTests", code: 1) }
            requestCount.mutate { $0 += 1 }
            let response = HTTPURLResponse(url: .userUpdate, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "0"])
            return (nil, response)
        })

        let expectation = XCTestExpectation(description: "Secure call finished")
        tokenHelper.callSecureUrl(request: URLRequest(url: .userUpdate)) { response, _, _ in
            XCTAssertEqual(response?.statusCode, 429, "A persistent 429 must surface to the caller after one retry")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 15)

        XCTAssertEqual(requestCount.value, 2, "Exactly one retry — never a loop")
    }

    func test429OnPasswordLoginRetriesOnce() async throws {
        ServerSettings.setSyncingEmail(email: "test@test.com")
        ServerSettings.saveSyncingPassword("1234")

        let requestCount = LockedBox(0)
        let responseData = try loginResponseData()

        let tokenHelper = TokenHelper(urlConnection: URLConnection { request in
            guard request.url == URL.userLogin else { throw NSError(domain: "TokenHelperTests", code: 1) }
            var count = 0
            requestCount.mutate { $0 += 1; count = $0 }
            if count == 1 {
                let response = HTTPURLResponse(url: .userLogin, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "0"])
                return (nil, response)
            }
            let response = HTTPURLResponse(url: .userLogin, statusCode: 200, httpVersion: nil, headerFields: nil)
            return (responseData, response)
        })

        let response = try await tokenHelper.acquirePasswordToken()

        XCTAssertEqual(response?.token, "1234")
        XCTAssertEqual(requestCount.value, 2)
    }

    // MARK: - Workstream A: migration state machine

    private func makeTokenHelper() -> TokenHelper {
        TokenHelper(urlConnection: URLConnection { _ in
            throw NSError(domain: "TokenHelperTests", code: 1)
        })
    }

    func testMigrationPersistsPairDeletesPasswordAndSetsMarker() throws {
        flagMock.set(.refreshTokenForPasswordAuth, value: true)
        ServerSettings.setSyncingEmail(email: "test@test.com")
        ServerSettings.saveSyncingPassword("1234")

        let response = AuthenticationResponse(token: "access", uuid: "uuid", email: "test@test.com", refreshToken: "new-refresh", isNewAccount: false, expiresIn: 3600, tokenType: "Bearer")
        makeTokenHelper().migratePasswordAccountIfPossible(response: response)

        XCTAssertNil(ServerSettings.syncingPassword(), "Migration must delete the stored password")
        XCTAssertEqual(try ServerSettings.refreshToken(), "new-refresh")
        XCTAssertEqual(ServerSettings.syncingV2Token, "access")
        XCTAssertEqual(ServerSettings.accountAuthMethod, .password)
        XCTAssertNotNil(ServerSettings.tokenExpiryDate())
    }

    func testMigrationKeepsPasswordWhenResponseLacksRefreshToken() throws {
        flagMock.set(.refreshTokenForPasswordAuth, value: true)
        ServerSettings.setSyncingEmail(email: "test@test.com")
        ServerSettings.saveSyncingPassword("1234")

        let response = AuthenticationResponse(token: "access", uuid: "uuid", email: "test@test.com", refreshToken: nil, isNewAccount: false, expiresIn: nil, tokenType: nil)
        makeTokenHelper().migratePasswordAccountIfPossible(response: response)

        XCTAssertEqual(ServerSettings.syncingPassword(), "1234", "Without a refresh token (server < M1) the password must survive so migration can retry later")
        XCTAssertNil(try ServerSettings.refreshToken())
        XCTAssertNil(ServerSettings.accountAuthMethod)
    }

    func testMigrationDoesNothingWhenFlagOff() throws {
        flagMock.set(.refreshTokenForPasswordAuth, value: false)
        ServerSettings.setSyncingEmail(email: "test@test.com")
        ServerSettings.saveSyncingPassword("1234")

        let response = AuthenticationResponse(token: "access", uuid: "uuid", email: "test@test.com", refreshToken: "new-refresh", isNewAccount: false, expiresIn: 3600, tokenType: "Bearer")
        makeTokenHelper().migratePasswordAccountIfPossible(response: response)

        XCTAssertEqual(ServerSettings.syncingPassword(), "1234")
        XCTAssertNil(try ServerSettings.refreshToken())
        XCTAssertNil(ServerSettings.accountAuthMethod)
    }

    func testFlagOnPrefersRefreshGrantOverStoredPassword() throws {
        flagMock.set(.refreshTokenForPasswordAuth, value: true)
        ServerSettings.setSyncingEmail(email: "test@test.com")
        ServerSettings.saveSyncingPassword("1234")
        ServerSettings.setRefreshToken("existing-refresh")

        let grantBody = try tokenLoginResponseData(accessToken: "grant-token", refreshToken: "rotated-refresh")
        TokenGrantURLProtocol.stub = { _ in
            TokenGrantURLProtocol.StubResponse(statusCode: 200, body: grantBody)
        }

        let loginRequestCount = LockedBox(0)
        let tokenHelper = TokenHelper(urlConnection: URLConnection { _ in
            loginRequestCount.mutate { $0 += 1 }
            throw NSError(domain: "TokenHelperTests", code: 1)
        })

        let token = acquireTokenOnBackgroundQueue(tokenHelper)

        XCTAssertEqual(token, "grant-token")
        XCTAssertEqual(loginRequestCount.value, 0, "With a refresh token present the password path must not run")
        XCTAssertEqual(try ServerSettings.refreshToken(), "rotated-refresh")
        XCTAssertEqual(ServerSettings.syncingPassword(), "1234", "The refresh-grant path never touches the stored password; migration handles its removal")
    }

    func testFlagOffUsesPasswordFirst() throws {
        flagMock.set(.refreshTokenForPasswordAuth, value: false)
        ServerSettings.setSyncingEmail(email: "test@test.com")
        ServerSettings.saveSyncingPassword("1234")
        ServerSettings.setRefreshToken("existing-refresh")

        let responseData = try loginResponseData(token: "password-token")
        let tokenHelper = TokenHelper(urlConnection: URLConnection { request in
            guard request.url == URL.userLogin else { throw NSError(domain: "TokenHelperTests", code: 1) }
            let response = HTTPURLResponse(url: .userLogin, statusCode: 200, httpVersion: nil, headerFields: nil)
            return (responseData, response)
        })

        let token = acquireTokenOnBackgroundQueue(tokenHelper)

        XCTAssertEqual(token, "password-token")
        XCTAssertEqual(TokenGrantURLProtocol.requestCount, 0, "Flag off must keep today's password-first order")
    }
}
