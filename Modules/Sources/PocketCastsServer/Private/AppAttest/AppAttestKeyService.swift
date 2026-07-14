import DeviceCheck
import Foundation

/// Seam over `DCAppAttestService` so unit tests can script key operations
/// (generate/attest/assert) without Secure Enclave hardware.
///
/// The `DeviceCheckAppAttestAdapter` below is the only code in the repo allowed
/// to touch `DCAppAttestService` directly — everything else must go through
/// `AppAttestService`, which owns the key's keychain persistence and
/// enrollment/rejection lifecycle. Enforced by the
/// `pocketcasts.app-attest-single-owner` Semgrep rule.
protocol AppAttestKeyService: Sendable {
    /// `false` on Simulator and in dev contexts where attestation is
    /// unavailable; such builds send requests unattested (docs/AppAttest.md).
    var isSupported: Bool { get }

    /// Generates a new hardware-bound key pair, returning its opaque keyId
    /// (base64 SHA-256 of the public key).
    func generateKey() async throws -> String

    /// Produces the Apple-signed attestation object for a freshly generated key.
    /// `clientDataHash` must be SHA256 of the server-issued challenge bytes.
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data

    /// Signs `clientDataHash` (SHA256 of the request body bytes) with the
    /// enrolled key, returning the CBOR assertion.
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data
}

/// Production adapter over the system App Attest service. Stateless: every call
/// goes straight to `DCAppAttestService.shared`.
struct DeviceCheckAppAttestAdapter: AppAttestKeyService {
    var isSupported: Bool {
        DCAppAttestService.shared.isSupported
    }

    func generateKey() async throws -> String {
        try await DCAppAttestService.shared.generateKey()
    }

    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.attestKey(keyId, clientDataHash: clientDataHash)
    }

    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: clientDataHash)
    }
}
