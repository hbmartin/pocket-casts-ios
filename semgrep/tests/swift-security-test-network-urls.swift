import Foundation

// Fixture for pocketcasts.no-real-network-hosts-in-tests: test download URLs must not
// point at real internet hosts; use RFC 2606 reserved names or RFC 5737 TEST-NET addresses.
class TestNetworkUrlsFixture {
    var downloadUrl: String?

    func badRealHostDownloadUrl() {
        // ruleid: pocketcasts.no-real-network-hosts-in-tests
        downloadUrl = "http://google.com"
    }

    func badRealHostHttps() {
        // ruleid: pocketcasts.no-real-network-hosts-in-tests
        downloadUrl = "https://www.apple.com/podcast.mp3"
    }

    func badExampleComCountryCodeBypass() {
        // ruleid: pocketcasts.no-real-network-hosts-in-tests
        downloadUrl = "https://example.com.co/episode.mp3"
    }

    func badReservedTestCountryCodeBypass() {
        // ruleid: pocketcasts.no-real-network-hosts-in-tests
        downloadUrl = "https://fixtures.test.co/episode.mp3"
    }

    func badLocalhostSubdomainBypass() {
        // ruleid: pocketcasts.no-real-network-hosts-in-tests
        downloadUrl = "http://localhost.evil.com/episode.mp3"
    }

    func badLoopbackPrefixBypass() {
        // ruleid: pocketcasts.no-real-network-hosts-in-tests
        downloadUrl = "http://127.evil.com/episode.mp3"
    }

    func badTestNetPrefixBypass() {
        // ruleid: pocketcasts.no-real-network-hosts-in-tests
        downloadUrl = "http://192.0.2.1.evil.com/episode.mp3"
    }

    func badExampleUserinfoBypass() {
        // ruleid: pocketcasts.no-real-network-hosts-in-tests
        downloadUrl = "https://example.com@evil.com/episode.mp3"
    }

    func badLocalhostUserinfoBypass() {
        // ruleid: pocketcasts.no-real-network-hosts-in-tests
        downloadUrl = "http://localhost@evil.com/episode.mp3"
    }

    func badLoopbackUserinfoBypass() {
        // ruleid: pocketcasts.no-real-network-hosts-in-tests
        downloadUrl = "http://127.0.0.1@evil.com/episode.mp3"
    }

    func badExamplePasswordUserinfoBypass() {
        // ruleid: pocketcasts.no-real-network-hosts-in-tests
        downloadUrl = "https://example.com:pass@evil.com/episode.mp3"
    }

    func badLocalhostPasswordUserinfoBypass() {
        // ruleid: pocketcasts.no-real-network-hosts-in-tests
        downloadUrl = "http://localhost:pw@evil.com/episode.mp3"
    }

    func badLoopbackPasswordUserinfoBypass() {
        // ruleid: pocketcasts.no-real-network-hosts-in-tests
        downloadUrl = "http://127.0.0.1:pw@evil.com/episode.mp3"
    }

    func goodReservedExampleHost() {
        // ok: pocketcasts.no-real-network-hosts-in-tests
        downloadUrl = "https://example.com/remote-podcast.mp3"
    }

    func goodReservedExampleSubdomain() {
        // ok: pocketcasts.no-real-network-hosts-in-tests
        downloadUrl = "https://cdn.example.com/episode1.mp3"
    }

    func goodTestNetAddress() {
        // ok: pocketcasts.no-real-network-hosts-in-tests
        downloadUrl = "http://192.0.2.1/episode.mp3"
    }

    func goodLocalhost() {
        // ok: pocketcasts.no-real-network-hosts-in-tests
        downloadUrl = "http://localhost:8080/episode.mp3"
    }

    func goodLoopbackAddressWithPort() {
        // ok: pocketcasts.no-real-network-hosts-in-tests
        downloadUrl = "http://127.0.0.1:8080/episode.mp3"
    }

    func goodAtSignInPathNotUserinfo() {
        // ok: pocketcasts.no-real-network-hosts-in-tests
        downloadUrl = "https://example.com/user@domain/episode.mp3"
    }

    func goodAtSignInQueryNotUserinfo() {
        // ok: pocketcasts.no-real-network-hosts-in-tests
        downloadUrl = "https://example.com/episode.mp3?from=@mention"
    }
}
