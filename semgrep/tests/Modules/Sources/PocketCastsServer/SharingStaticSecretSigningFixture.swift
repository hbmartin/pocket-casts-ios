import CryptoKit
import Foundation

// Fixture for pocketcasts.sharing-no-static-secret-signing. It lives under a
// Modules/Sources/PocketCastsServer-shaped path because the rule is scoped to the
// server module; the SHA-1 lines also (intentionally) trip the repo-wide
// pocketcasts.no-insecure-cryptokit-hashes rule, so both ids are annotated.
enum ReintroducedSharingSignature {
    static func timestampSignature(for dateString: String, credential: String) -> String {
        // ruleid: pocketcasts.sharing-no-static-secret-signing, pocketcasts.no-insecure-cryptokit-hashes
        let digest = Insecure.SHA1.hash(data: Data("\(dateString)\(credential)".utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    static func qualifiedTimestampSignature(data: Data) {
        // ruleid: pocketcasts.sharing-no-static-secret-signing, pocketcasts.no-insecure-cryptokit-hashes
        _ = CryptoKit.Insecure.SHA1.hash(data: data)
    }

    static func embeddedSharedCredential() -> String {
        // ruleid: pocketcasts.sharing-no-static-secret-signing
        return ServerCredentials.sharing
    }

    static func bearerPathDigest(data: Data) -> String {
        // ok: pocketcasts.sharing-no-static-secret-signing
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
