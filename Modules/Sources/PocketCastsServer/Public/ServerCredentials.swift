import Foundation

// M3: delete this whole type when the sharing server's legacy `h` signature is disabled
// (plans/API Auth Hardening Plan.md §3.4). Removal checklist for that milestone:
// - the `configureSharing` call in podcasts/AppDelegate.swift
// - `sharingServerSecret` in podcasts/Credentials/ApiCredentials.tpl and
//   scripts/generate-placeholder-credentials.sh
// - the `sharing_server_secret` required key in scripts/ci/prepare-credentials.sh and
//   scripts/tests/generate_credentials_test.rb, and the regenerated
//   .configure-files/pocket_casts_credentials.json.enc blob (rotate the old secret dead)
// - the Semgrep rule pocketcasts.servercredentials-use-configure-sharing and its fixture
//   (replaced by pocketcasts.sharing-no-static-secret-signing)
public enum ServerCredentials {
    private static let lock = NSLock()

    /// Secret needed to share one or more podcasts
    // nonisolated(unsafe): written once during app startup from generated credentials.
    nonisolated(unsafe) public private(set) static var sharing = ""

    // nonisolated(unsafe): written once under `lock` during app startup, alongside `sharing`.
    nonisolated(unsafe) private static var hasConfiguredSharing = false

    public static func configureSharing(_ value: String) {
        lock.lock()
        defer { lock.unlock() }

        precondition(!hasConfiguredSharing, "ServerCredentials.sharing configured more than once")
        sharing = value
        hasConfiguredSharing = true
    }
}
