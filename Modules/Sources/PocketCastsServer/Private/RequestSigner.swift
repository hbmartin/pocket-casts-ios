import CryptoKit
import Foundation
import PocketCastsUtils
import Security
import Synchronization

enum RequestSignerError: Error {
    /// `SecAccessControlCreateWithFlags` rejected the Secure Enclave access-control flags.
    case accessControlCreationFailed
    /// The key material could not be written to the keychain.
    case keyPersistenceFailed
}

/// Per-install P-256 signing key and DPoP (RFC 9449) proof builder.
///
/// This is Phase 1 of Workstream C.1 in `plans/API Auth Hardening Plan.md` (§4.3):
/// self-contained client key material with **no** endpoint wiring. No production
/// code path calls `makeProof(htm:htu:accessToken:)` yet, so no feature flag is
/// needed — the type is dormant until Phase 2 lands.
///
/// Activation plan:
/// - **Phase 2** (server + client): attach a `DPoP` proof header on `user/login`,
///   `user/register`, and `user/token` so the server can bind issued tokens to this
///   install's key. `jwkThumbprint()` is the RFC 7638 `jkt` value the server stores
///   on the token/refresh-family record; `isSecureEnclaveBacked` feeds the proof
///   JWK annotation so the server can risk-score software-key installs.
/// - **Phase 3** (server + client): attach proofs — including the `ath` access-token
///   hash claim — on high-value resource endpoints (change email/password, delete
///   account, token revoke, Sonos exchange, upload presign).
///
/// Key storage: the private key is generated lazily on first use and held in the
/// Secure Enclave when available (`SecureEnclave.P256.Signing.PrivateKey`, access
/// control `.privateKeyUsage` with deliberately **no** user-presence requirement,
/// because background refresh must be able to sign while the device is locked).
/// The Secure Enclave's encrypted key blob — or, where the enclave is unavailable
/// (simulator), the raw representation of a software fallback key — is persisted
/// through `KeychainHelper` with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`,
/// so the key never leaves this device via backup. That is intentional: per plan
/// §4.3 Phase 2, a backup restored onto another device loses the key, the bound
/// refresh token stops validating, and the user signs in cleanly again.
///
/// Concurrency: CryptoKit key types are not Sendable-friendly on every SDK, so the
/// key is confined inside a `Mutex` and never escapes it — signing happens under
/// the lock and only `Sendable` values (`String`/`Bool`) are returned. That keeps
/// this final class `Sendable` without any unchecked opt-outs.
///
/// Security invariant: never log or expose private key material or access tokens
/// from this type. Log messages must stay generic.
final class RequestSigner: Sendable {
    static let shared = RequestSigner()

    private enum SigningKey {
        case secureEnclave(SecureEnclave.P256.Signing.PrivateKey)
        case software(P256.Signing.PrivateKey)

        var isSecureEnclaveBacked: Bool {
            if case .secureEnclave = self {
                return true
            }
            return false
        }

        var publicKey: P256.Signing.PublicKey {
            switch self {
            case .secureEnclave(let key):
                key.publicKey
            case .software(let key):
                key.publicKey
            }
        }

        /// ES256: ECDSA over P-256; CryptoKit hashes the data with SHA-256 internally.
        func signature(for data: Data) throws -> P256.Signing.ECDSASignature {
            switch self {
            case .secureEnclave(let key):
                try key.signature(for: data)
            case .software(let key):
                try key.signature(for: data)
            }
        }
    }

    private struct JSONWebKey: Encodable {
        let kty = "EC"
        let crv = "P-256"
        let x: String
        let y: String
    }

    private struct ProofHeader: Encodable {
        let typ = "dpop+jwt"
        let alg = "ES256"
        let jwk: JSONWebKey
    }

    private struct ProofClaims: Encodable {
        let htm: String
        let htu: String
        let iat: Int
        let jti: String
        /// base64url(SHA-256(access token)), RFC 9449 §4.3. Omitted when no token is presented.
        let ath: String?
    }

    private static let keychainKey = "SJDPoPSigningKey"
    private static let secureEnclaveBlobPrefix = "se:"
    private static let softwareKeyPrefix = "sw:"

    /// The signing key, created lazily on first use and cached for the process
    /// lifetime. Confined to the mutex; see the type documentation.
    private let cachedKey = Mutex<SigningKey?>(nil)

    /// Test seam: a fixed software key for deterministic vectors. When set, the
    /// keychain is never read or written.
    private let injectedSoftwareKey: P256.Signing.PrivateKey?

    init() {
        injectedSoftwareKey = nil
    }

    /// Creates a signer over a fixed software key. Test-only: bypasses the Secure
    /// Enclave and keychain persistence entirely so vectors are deterministic.
    init(softwareKey: P256.Signing.PrivateKey) {
        injectedSoftwareKey = softwareKey
    }

    /// Whether the per-install key lives in the Secure Enclave. `false` means the
    /// software fallback is in use; Phase 2 reports this alongside the proof JWK so
    /// the server can risk-score the install. Accessing this creates the key if it
    /// does not exist yet.
    var isSecureEnclaveBacked: Bool {
        get throws {
            try withSigningKey { $0.isSecureEnclaveBacked }
        }
    }

    /// Builds a DPoP proof JWT (RFC 9449) over the given request coordinates.
    ///
    /// - Parameters:
    ///   - htm: The HTTP method of the request the proof covers (e.g. `"POST"`).
    ///   - htu: The request URL; it is canonicalized to scheme + host + path with
    ///     query and fragment dropped, per RFC 9449 §4.2.
    ///   - accessToken: When the request also carries an access token, pass it so
    ///     the proof binds to it via the `ath` claim (RFC 9449 §4.3). Never stored
    ///     or logged.
    /// - Returns: The compact-serialized proof (`header.claims.signature`, base64url
    ///   without padding) for the `DPoP` request header.
    func makeProof(htm: String, htu: URL, accessToken: String? = nil) throws -> String {
        let claims = ProofClaims(
            htm: htm,
            htu: Self.canonicalHTU(for: htu),
            iat: Int(Date().timeIntervalSince1970),
            jti: UUID().uuidString,
            ath: accessToken.map { Self.base64URL(Data(SHA256.hash(data: Data($0.utf8)))) }
        )

        return try withSigningKey { key in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

            let headerSegment = Self.base64URL(try encoder.encode(ProofHeader(jwk: Self.jwk(for: key.publicKey))))
            let claimsSegment = Self.base64URL(try encoder.encode(claims))
            let signature = try key.signature(for: Data("\(headerSegment).\(claimsSegment)".utf8))

            return "\(headerSegment).\(claimsSegment).\(Self.base64URL(signature.rawRepresentation))"
        }
    }

    /// RFC 7638 JWK thumbprint of the per-install public key: SHA-256 over the JSON
    /// object holding only the required EC members (`crv`, `kty`, `x`, `y`) in
    /// lexicographic order with no whitespace, base64url-encoded without padding.
    /// This is the `jkt` value the server binds tokens to in Phase 2.
    func jwkThumbprint() throws -> String {
        try withSigningKey { key in
            let jwk = Self.jwk(for: key.publicKey)
            let canonical = "{\"crv\":\"\(jwk.crv)\",\"kty\":\"\(jwk.kty)\",\"x\":\"\(jwk.x)\",\"y\":\"\(jwk.y)\"}"
            return Self.base64URL(Data(SHA256.hash(data: Data(canonical.utf8))))
        }
    }

    // MARK: - Canonicalization

    /// RFC 9449 `htu`: the target URI without query and fragment. Scheme and host
    /// are lowercased per RFC 3986; userinfo is dropped because it is not part of
    /// the HTTP target URI.
    static func canonicalHTU(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return url.absoluteString
        }

        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()

        return components.string ?? url.absoluteString
    }

    // MARK: - Key management

    /// Runs `body` with the signing key while it is confined to the mutex, creating
    /// and persisting the key first if this install does not have one yet.
    private func withSigningKey<T: Sendable>(_ body: (SigningKey) throws -> T) throws -> T {
        try cachedKey.withLock { cached in
            if let cached {
                return try body(cached)
            }

            let key: SigningKey
            if let injectedSoftwareKey {
                key = .software(injectedSoftwareKey)
            } else {
                key = try Self.loadOrCreateKey()
            }

            cached = key
            return try body(key)
        }
    }

    private static func loadOrCreateKey() throws -> SigningKey {
        if let persisted = try? KeychainHelper.string(for: keychainKey),
           let key = decodePersistedKey(persisted) {
            return key
        }

        // An unreadable blob is regenerated: in Phase 1 nothing is bound to the key
        // yet, so a fresh key is harmless. Phase 2 must revisit this — once tokens
        // are bound, losing the key unbinds them and forces a clean re-login.
        return try createAndPersistKey()
    }

    private static func decodePersistedKey(_ persisted: String) -> SigningKey? {
        if persisted.hasPrefix(secureEnclaveBlobPrefix) {
            guard SecureEnclave.isAvailable,
                  let blob = Data(base64Encoded: String(persisted.dropFirst(secureEnclaveBlobPrefix.count))),
                  let key = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob) else {
                FileLog.shared.addMessage("RequestSigner: persisted Secure Enclave key blob could not be loaded, generating a new key")
                return nil
            }

            return .secureEnclave(key)
        }

        if persisted.hasPrefix(softwareKeyPrefix) {
            guard let raw = Data(base64Encoded: String(persisted.dropFirst(softwareKeyPrefix.count))),
                  let key = try? P256.Signing.PrivateKey(rawRepresentation: raw) else {
                FileLog.shared.addMessage("RequestSigner: persisted software key could not be loaded, generating a new key")
                return nil
            }

            return .software(key)
        }

        FileLog.shared.addMessage("RequestSigner: persisted key had an unknown format, generating a new key")
        return nil
    }

    private static func createAndPersistKey() throws -> SigningKey {
        if secureEnclaveUsable {
            var accessControlError: Unmanaged<CFError>?
            // .privateKeyUsage only — deliberately no user-presence/biometry flag,
            // because background refresh must sign proofs while the device is locked
            // (plan §4.3 Phase 1).
            guard let accessControl = SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                .privateKeyUsage,
                &accessControlError
            ) else {
                if let cfError = accessControlError?.takeRetainedValue() {
                    FileLog.shared.addMessage("RequestSigner: access control creation failed: \((cfError as Error).localizedDescription)")
                }
                throw RequestSignerError.accessControlCreationFailed
            }

            if let key = try? SecureEnclave.P256.Signing.PrivateKey(accessControl: accessControl) {
                // dataRepresentation is the enclave's encrypted key blob, not the
                // private scalar; only the Secure Enclave can use it, and only on
                // this device.
                try persist(prefix: secureEnclaveBlobPrefix, keyMaterial: key.dataRepresentation)
                return .secureEnclave(key)
            }

            // The enclave reported available but key creation failed; fall back so
            // signing still works. The server can risk-score this via the Phase 2
            // JWK annotation (isSecureEnclaveBacked == false).
            FileLog.shared.addMessage("RequestSigner: Secure Enclave key creation failed, falling back to a software key")
        }

        let key = P256.Signing.PrivateKey()
        try persist(prefix: softwareKeyPrefix, keyMaterial: key.rawRepresentation)
        return .software(key)
    }

    private static func persist(prefix: String, keyMaterial: Data) throws {
        let stored = prefix + keyMaterial.base64EncodedString()
        guard KeychainHelper.save(string: stored, key: keychainKey, accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly) else {
            throw RequestSignerError.keyPersistenceFailed
        }
    }

    /// Whether to create the key in the Secure Enclave. Forced off on the simulator:
    /// even where newer simulator runtimes emulate an enclave it is not hardware
    /// backed, and a deterministic software path keeps test behavior stable.
    private static var secureEnclaveUsable: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        SecureEnclave.isAvailable
        #endif
    }

    // MARK: - Encoding

    /// base64url without padding (RFC 7515 §2), as required for JWS segments, `ath`,
    /// and the JWK coordinates/thumbprint.
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func jwk(for publicKey: P256.Signing.PublicKey) -> JSONWebKey {
        // rawRepresentation is X || Y as two fixed-width 32-byte big-endian coordinates.
        let raw = publicKey.rawRepresentation
        return JSONWebKey(
            x: base64URL(raw.prefix(32)),
            y: base64URL(raw.suffix(32))
        )
    }
}
