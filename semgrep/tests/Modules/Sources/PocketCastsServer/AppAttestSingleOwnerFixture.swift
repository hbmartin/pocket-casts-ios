// Fixture for pocketcasts.app-attest-single-owner: DCAppAttestService may only
// be touched by the adapter inside Modules/Sources/PocketCastsServer/Private/AppAttest
// (that path is excluded from the rule); everywhere else must go through
// AppAttestService so the key lifecycle keeps a single owner (docs/AppAttest.md §1).
import DeviceCheck
import Foundation

func badDirectKeyGeneration() async throws -> String {
    // ruleid: pocketcasts.app-attest-single-owner
    try await DCAppAttestService.shared.generateKey()
}

func badDirectSupportCheck() -> Bool {
    // ruleid: pocketcasts.app-attest-single-owner
    DCAppAttestService.shared.isSupported
}

func badStashedServiceReference() {
    // ruleid: pocketcasts.app-attest-single-owner
    let service = DCAppAttestService.shared
    _ = service
}

func goodRoutedAttestation(body: Data) async -> [String: String] {
    // ok: pocketcasts.app-attest-single-owner
    await AppAttestService.shared.assertionHeaders(forBody: body)
}

func goodRejectionHandling() async {
    // ok: pocketcasts.app-attest-single-owner
    await AppAttestService.shared.handleAttestationRejection()
}
