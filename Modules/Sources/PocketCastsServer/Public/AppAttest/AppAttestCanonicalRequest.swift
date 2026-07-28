import CryptoKit
import Foundation

enum AppAttestCanonicalRequestError: Error, Equatable {
    case missingURL
    case nonCanonicalPath
    case invalidQueryEncoding
}

enum AppAttestRoutePolicy {
    static func isSelfHosted(_ request: URLRequest, origin: URL?) -> Bool {
        guard let url = request.url, let origin,
              url.scheme?.lowercased() == origin.scheme?.lowercased(),
              url.host?.lowercased() == origin.host?.lowercased(),
              effectivePort(url) == effectivePort(origin)
        else {
            return false
        }
        return true
    }

    static func requiresAttestation(_ request: URLRequest, origin: URL?) -> Bool {
        guard isSelfHosted(request, origin: origin), let url = request.url else { return false }

        if request.value(forHTTPHeaderField: ServerConstants.HttpHeaders.authorization)?.hasPrefix("Bearer ") == true {
            return true
        }

        switch url.path {
        case "/attest/challenge", "/attest/enroll", "/livez", "/health.html",
             "/apple-app-site-association", "/.well-known/apple-app-site-association":
            return false
        default:
            break
        }


        // Bare "/podcast/" and "/episode/" are deliberately absent: every public
        // catalogue read uses "/mobile/..." paths, while native API routes such as
        // "/podcast/suggest_folders" must stay attested even when sent anonymously.
        let publicPrefixes = [
            "/discover/", "/podcasts/search", "/podcasts/show", "/mobile/",
            "/search/", "/autocomplete/", "/episode/search", "/podcast/rating/",
            "/share/", "/u/", "/profile/", "/images/"
        ]
        if publicPrefixes.contains(where: { url.path.hasPrefix($0) }) {
            return url.path == "/discover/recommend_episodes"
        }

        return true
    }

    private static func effectivePort(_ url: URL) -> Int? {
        if let port = url.port { return port }
        return url.scheme?.lowercased() == "https" ? 443 : 80
    }
}

enum AppAttestCanonicalRequest {
    static func data(for request: URLRequest) throws -> Data {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            throw AppAttestCanonicalRequestError.missingURL
        }

        let decodedPath = url.path.isEmpty ? "/" : url.path
        guard decodedPath.hasPrefix("/"),
              !decodedPath.contains("\\"),
              !decodedPath.contains("//"),
              !decodedPath.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == "." || $0 == ".." })
        else {
            throw AppAttestCanonicalRequestError.nonCanonicalPath
        }

        let canonicalPath = percentEncode(decodedPath, allowingSlash: true)
        let suppliedPath = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        guard suppliedPath == canonicalPath else {
            throw AppAttestCanonicalRequestError.nonCanonicalPath
        }

        let query = try canonicalQuery(components.percentEncodedQuery)
        let bodyHash = SHA256.hash(data: request.httpBody ?? Data()).map { String(format: "%02x", $0) }.joined()
        let method = (request.httpMethod ?? "GET").uppercased()
        return Data("v1\n\(method)\n\(canonicalPath)\n\(query)\n\(bodyHash)".utf8)
    }

    private static func canonicalQuery(_ rawQuery: String?) throws -> String {
        guard let rawQuery, !rawQuery.isEmpty else { return "" }
        var pairs = [(key: String, value: String)]()
        for component in rawQuery.split(separator: "&", omittingEmptySubsequences: false) {
            let pieces = component.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = decodeFormComponent(String(pieces[0])) else {
                throw AppAttestCanonicalRequestError.invalidQueryEncoding
            }
            let rawValue = pieces.count == 2 ? String(pieces[1]) : ""
            guard let value = decodeFormComponent(rawValue) else {
                throw AppAttestCanonicalRequestError.invalidQueryEncoding
            }
            pairs.append((percentEncode(key), percentEncode(value)))
        }
        pairs.sort { lhs, rhs in
            lhs.key == rhs.key ? lhs.value < rhs.value : lhs.key < rhs.key
        }
        return pairs.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
    }

    private static func decodeFormComponent(_ value: String) -> String? {
        value.replacingOccurrences(of: "+", with: "%20").removingPercentEncoding
    }

    private static func percentEncode(_ value: String, allowingSlash: Bool = false) -> String {
        var result = ""
        result.reserveCapacity(value.utf8.count)
        for byte in value.utf8 {
            let isUnreserved = (byte >= 65 && byte <= 90)
                || (byte >= 97 && byte <= 122)
                || (byte >= 48 && byte <= 57)
                || byte == 45 || byte == 46 || byte == 95 || byte == 126
            if isUnreserved || (allowingSlash && byte == 47) {
                result.unicodeScalars.append(UnicodeScalar(byte))
            } else {
                result += String(format: "%%%02X", byte)
            }
        }
        return result
    }
}
