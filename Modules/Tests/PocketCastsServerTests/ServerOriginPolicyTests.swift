import Foundation
@testable import PocketCastsServer
import XCTest

final class ServerOriginPolicyTests: XCTestCase {
    func testAcceptsHTTPSRootAndNormalizesCaseAndSlash() {
        XCTAssertEqual(
            ServerOriginPolicy.normalizedOrigin(" HTTPS://Podcasts.Example:8443 ", allowInsecureLoopback: false),
            "https://podcasts.example:8443/"
        )
    }

    func testRejectsCredentialsPathQueryFragmentAndInsecureRemoteHost() {
        let invalid = [
            "https://user:password@podcasts.example",
            "https://podcasts.example/api",
            "https://podcasts.example?x=1",
            "https://podcasts.example/#fragment",
            "http://podcasts.example",
        ]
        for value in invalid {
            XCTAssertNil(ServerOriginPolicy.normalizedOrigin(value, allowInsecureLoopback: true), value)
        }
    }

    func testAllowsHTTPOnlyForExplicitLoopbackDebugConfiguration() {
        XCTAssertEqual(
            ServerOriginPolicy.normalizedOrigin("http://127.0.0.1:8000", allowInsecureLoopback: true),
            "http://127.0.0.1:8000/"
        )
        XCTAssertNil(ServerOriginPolicy.normalizedOrigin("http://127.0.0.1:8000", allowInsecureLoopback: false))
    }

    func testNonPinningOverrideNeitherReadsNorWritesTheInstalledOrigin() throws {
        let suite = "ServerOriginPolicyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // A pinned origin from a normal launch must not block a debug override…
        _ = ServerOriginPolicy(buildOrigin: "https://one.example", defaults: defaults, allowInsecureLoopback: false)
        let overridden = ServerOriginPolicy(
            buildOrigin: "http://127.0.0.1:8000",
            defaults: defaults,
            allowInsecureLoopback: true,
            pinsOrigin: false
        )
        XCTAssertEqual(overridden.state, .ready(origin: "http://127.0.0.1:8000/"))

        // …and the override must not disturb the pin for later normal launches.
        XCTAssertEqual(defaults.string(forKey: ServerOriginPolicy.installedOriginDefaultsKey), "https://one.example/")
        let normal = ServerOriginPolicy(buildOrigin: "https://one.example", defaults: defaults, allowInsecureLoopback: false)
        XCTAssertEqual(normal.state, .ready(origin: "https://one.example/"))
    }

    func testChangingBuildOriginRequiresReinstallWithoutOverwritingInstalledValue() throws {
        let suite = "ServerOriginPolicyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let initial = ServerOriginPolicy(buildOrigin: "https://one.example", defaults: defaults, allowInsecureLoopback: false)
        XCTAssertEqual(initial.state, .ready(origin: "https://one.example/"))

        let updated = ServerOriginPolicy(buildOrigin: "https://two.example", defaults: defaults, allowInsecureLoopback: false)
        XCTAssertEqual(
            updated.state,
            .reinstallRequired(installed: "https://one.example/", build: "https://two.example/")
        )
        XCTAssertFalse(updated.isNetworkAllowed)
        XCTAssertEqual(defaults.string(forKey: ServerOriginPolicy.installedOriginDefaultsKey), "https://one.example/")
    }

    func testSameOriginRejectsCredentialBearingURLs() throws {
        let policy = ServerOriginPolicy(
            buildOrigin: "https://podcasts.example",
            defaults: try XCTUnwrap(UserDefaults(suiteName: "ServerOriginPolicyTests.ephemeral")),
            allowInsecureLoopback: false,
            pinsOrigin: false
        )

        XCTAssertTrue(policy.isSameOrigin(try XCTUnwrap(URL(string: "https://podcasts.example/resource"))))
        XCTAssertFalse(policy.isSameOrigin(try XCTUnwrap(URL(string: "https://user@podcasts.example/resource"))))
        XCTAssertFalse(policy.isSameOrigin(try XCTUnwrap(URL(string: "https://user:password@podcasts.example/resource"))))
    }
}
