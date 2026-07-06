import CryptoKit
import Foundation

nonisolated extension String {
    var sha256Hash: String {
        let hash = SHA256.hash(data: Data(utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return hash
    }
}
