import CryptoKit
import Foundation
@testable import PocketCastsServer
import PocketCastsUtils
import XCTest

final class RequestSignerTests: XCTestCase {
    /// Fixed software key: raw scalar bytes 0x01...0x20 (a valid P-256 scalar).
    /// The public coordinates, thumbprint, and ath vectors below were computed
    /// independently of RequestSigner (CryptoKit on the macOS host, cross-checked
    /// with Python hashlib/base64).
    private static let fixedKeyRawRepresentation = Data((1...32).map { UInt8($0) })
    private static let expectedX = "UVw9brnjlrkE0_7Kf1T9zQzB6Ze_N13KUVrQpsO0A18"
    private static let expectedY = "RTa-OlDzGPv5pUdZAqIhUCvvDVfgjFOyzApW8X2fk1Q"
    /// SHA-256 over {"crv":"P-256","kty":"EC","x":expectedX,"y":expectedY} per RFC 7638.
    private static let expectedThumbprint = "6UoWwDCkLjV0J-pQG8c0THxbVhBcpR0AZDift1Yl5DM"
    /// base64url(SHA-256("test-access-token")) per RFC 9449 §4.3.
    private static let expectedAth = "WXSA1LYsphIZPxnnP-TMOtF_C_nPwWp8v0tQZBMcSAU"

    private static let tokenEndpoint = URL(string: "https://api.pocketcasts.com/user/token")!

    private var previousKeychainStore: KeychainStoring!

    override func setUp() {
        super.setUp()
        previousKeychainStore = KeychainHelper.store
        KeychainHelper.store = InMemoryKeychainStore()
    }

    override func tearDown() {
        KeychainHelper.store = previousKeychainStore
        super.tearDown()
    }

    // MARK: - Proof shape

    func testProofHasThreeBase64URLSegments() throws {
        let proof = try makeFixedKeySigner().makeProof(htm: "POST", htu: Self.tokenEndpoint)

        let segments = proof.components(separatedBy: ".")
        XCTAssertEqual(segments.count, 3)

        for segment in segments {
            XCTAssertFalse(segment.isEmpty)
            XCTAssertNil(
                segment.rangeOfCharacter(from: Self.nonBase64URLCharacters),
                "JWS segments must be base64url without padding: \(segment)"
            )
        }
    }

    func testProofHeaderDeclaresDPoPJWTWithEmbeddedJWK() throws {
        let proof = try makeFixedKeySigner().makeProof(htm: "POST", htu: Self.tokenEndpoint)
        let header = try Self.decodeSegment(proof, at: 0)

        XCTAssertEqual(header["typ"] as? String, "dpop+jwt")
        XCTAssertEqual(header["alg"] as? String, "ES256")

        let jwk = try XCTUnwrap(header["jwk"] as? [String: Any])
        XCTAssertEqual(jwk["kty"] as? String, "EC")
        XCTAssertEqual(jwk["crv"] as? String, "P-256")
        XCTAssertEqual(jwk["x"] as? String, Self.expectedX)
        XCTAssertEqual(jwk["y"] as? String, Self.expectedY)
    }

    func testProofClaimsCarryRequestCoordinates() throws {
        let proof = try makeFixedKeySigner().makeProof(htm: "POST", htu: Self.tokenEndpoint)
        let claims = try Self.decodeSegment(proof, at: 1)

        XCTAssertEqual(claims["htm"] as? String, "POST")
        XCTAssertEqual(claims["htu"] as? String, "https://api.pocketcasts.com/user/token")

        let iat = try XCTUnwrap(claims["iat"] as? Int)
        XCTAssertEqual(Double(iat), Date().timeIntervalSince1970, accuracy: 60)

        let jti = try XCTUnwrap(claims["jti"] as? String)
        XCTAssertNotNil(UUID(uuidString: jti))
    }

    // MARK: - htu canonicalization

    func testHTUCanonicalizationDropsQueryAndFragment() throws {
        let messyUrl = URL(string: "HTTPS://API.Pocketcasts.com/user/token?grant=refresh_token&x=1#section")!

        XCTAssertEqual(RequestSigner.canonicalHTU(for: messyUrl), "https://api.pocketcasts.com/user/token")

        let proof = try makeFixedKeySigner().makeProof(htm: "POST", htu: messyUrl)
        let claims = try Self.decodeSegment(proof, at: 1)
        XCTAssertEqual(claims["htu"] as? String, "https://api.pocketcasts.com/user/token")
    }

    // MARK: - jti

    func testJTIIsUniqueAcrossProofs() throws {
        let signer = try makeFixedKeySigner()

        let first = try Self.decodeSegment(try signer.makeProof(htm: "POST", htu: Self.tokenEndpoint), at: 1)
        let second = try Self.decodeSegment(try signer.makeProof(htm: "POST", htu: Self.tokenEndpoint), at: 1)

        XCTAssertNotEqual(first["jti"] as? String, second["jti"] as? String)
    }

    // MARK: - ath

    func testAthIsOmittedWithoutAccessToken() throws {
        let proof = try makeFixedKeySigner().makeProof(htm: "POST", htu: Self.tokenEndpoint)
        let claims = try Self.decodeSegment(proof, at: 1)

        XCTAssertNil(claims["ath"])
    }

    func testAthMatchesAccessTokenHashVector() throws {
        let proof = try makeFixedKeySigner().makeProof(htm: "POST", htu: Self.tokenEndpoint, accessToken: "test-access-token")
        let claims = try Self.decodeSegment(proof, at: 1)

        XCTAssertEqual(claims["ath"] as? String, Self.expectedAth)
    }

    // MARK: - Thumbprint

    func testThumbprintIsStableAndMatchesVector() throws {
        let signer = try makeFixedKeySigner()

        XCTAssertEqual(try signer.jwkThumbprint(), Self.expectedThumbprint)
        XCTAssertEqual(try signer.jwkThumbprint(), try signer.jwkThumbprint())
    }

    // MARK: - Signature

    func testProofSignatureVerifiesWithPublicKey() throws {
        let privateKey = try P256.Signing.PrivateKey(rawRepresentation: Self.fixedKeyRawRepresentation)
        let signer = RequestSigner(softwareKey: privateKey)

        let proof = try signer.makeProof(htm: "POST", htu: Self.tokenEndpoint, accessToken: "test-access-token")
        let segments = proof.components(separatedBy: ".")
        XCTAssertEqual(segments.count, 3)

        let signingInput = Data("\(segments[0]).\(segments[1])".utf8)
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: XCTUnwrap(Self.decodeBase64URL(segments[2])))

        XCTAssertTrue(privateKey.publicKey.isValidSignature(signature, for: signingInput))
    }

    // MARK: - Key creation, persistence, and fallback

    func testDefaultSignerUsesPersistedSoftwareFallbackKey() throws {
        // The Secure Enclave is unavailable under test (simulator), so the signer
        // must fall back to a software key rather than fail.
        let signer = RequestSigner()
        let thumbprint = try signer.jwkThumbprint()

        #if targetEnvironment(simulator)
        XCTAssertFalse(try signer.isSecureEnclaveBacked)
        let persisted = try XCTUnwrap(KeychainHelper.string(for: "SJDPoPSigningKey"))
        XCTAssertTrue(persisted.hasPrefix("sw:"), "Software fallback keys persist their raw representation with the sw: prefix")
        #endif

        // A second signer (fresh cache, same keychain) must load the same key, not mint a new one.
        XCTAssertEqual(try RequestSigner().jwkThumbprint(), thumbprint)
    }

    // MARK: - Helpers

    private static let nonBase64URLCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_").inverted

    private func makeFixedKeySigner() throws -> RequestSigner {
        RequestSigner(softwareKey: try P256.Signing.PrivateKey(rawRepresentation: Self.fixedKeyRawRepresentation))
    }

    private static func decodeSegment(_ proof: String, at index: Int) throws -> [String: Any] {
        let segments = proof.components(separatedBy: ".")
        XCTAssertGreaterThan(segments.count, index)
        let data = try XCTUnwrap(decodeBase64URL(segments[index]))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func decodeBase64URL(_ segment: String) -> Data? {
        var base64 = segment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        return Data(base64Encoded: base64)
    }
}
