import CryptoKit
import Foundation

func badMD5Checksum(data: Data) {
    // ruleid: pocketcasts.no-insecure-cryptokit-hashes
    _ = Insecure.MD5.hash(data: data)
}

func badSHA1Checksum(data: Data) {
    // ruleid: pocketcasts.no-insecure-cryptokit-hashes
    _ = Insecure.SHA1.hash(data: data)
}

func badQualifiedSHA1Checksum(data: Data) {
    // ruleid: pocketcasts.no-insecure-cryptokit-hashes
    _ = CryptoKit.Insecure.SHA1.hash(data: data)
}

func goodSHA256Digest(data: Data) {
    // ok: pocketcasts.no-insecure-cryptokit-hashes
    _ = SHA256.hash(data: data)
}

enum CopiedSharingServerHandler {
    static func legacySharingServerSignature(for dateString: String, credential: String) -> String {
        // ruleid: pocketcasts.no-insecure-cryptokit-hashes
        let hashDigest = CryptoKit.Insecure.SHA1.hash(data: Data("\(dateString)\(credential)".utf8))
        return hashDigest.map { String(format: "%02hhx", $0) }.joined()
    }
}
