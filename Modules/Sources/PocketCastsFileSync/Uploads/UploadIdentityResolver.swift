import Foundation
import CryptoKit

/// Computes the canonical content identity of upload files.
public enum UploadIdentityResolver {
    /// Streaming SHA-256 of a local file, lowercase hex. Reads in 1 MB
    /// chunks so multi-GB audiobooks don't spike memory.
    public static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            guard let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
