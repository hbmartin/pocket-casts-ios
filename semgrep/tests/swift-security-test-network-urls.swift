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
}
