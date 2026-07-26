import Foundation
import PocketCastsUtils

/// Uploads a user's avatar image and maps the mandatory nudity/racy scan verdict
/// (docs/SocialModeration.md, ADR-0007). Modeled on `TranscriptUploadSender`:
/// raw image bytes as `application/octet-stream`, Bearer auth (required — an
/// avatar upload needs a joined, signed-in account), and App Attest assertion
/// headers signing the exact body bytes (docs/AppAttest.md §1.3). The scan runs
/// server-side before any CDN publish; this only surfaces the outcome. Ships
/// dark behind FeatureFlag.socialProfiles.
///
/// Slice-1 scaffolding: the happy path + scan-verdict mapping. The richer
/// attestation-envelope handling (invalid/stale assertion retries) that
/// `TranscriptUploadSender` performs is deferred until the endpoint is live.
public struct SocialAvatarUploadSender: Sendable {
    private let urlConnection: URLConnection

    public init(urlConnection: URLConnection = URLConnection(handler: URLSession.shared)) {
        self.urlConnection = urlConnection
    }

    /// POSTs the image bytes (JPEG/PNG) to `social/avatar` and returns the scan
    /// result. `.failed` covers "not signed in", transport failure and any
    /// non-OK status; the rejection cases are the server's scan verdict.
    public func upload(imageData: Data) async -> SocialAvatarUploadResult {
        guard SyncManager.isUserLoggedIn(), let token = await Self.bearerToken() else {
            return .failed
        }
        guard let url = URL(string: "\(ServerConstants.Urls.api())social/avatar") else {
            return .failed
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: ServerConstants.Timeouts.general)
        request.httpMethod = "POST"
        request.httpBody = imageData
        request.setValue("application/octet-stream", forHTTPHeaderField: ServerConstants.HttpHeaders.contentType)
        request.addValue("application/octet-stream", forHTTPHeaderField: ServerConstants.HttpHeaders.accept)
        request.setValue(ServerConfig.shared.syncDelegate?.privateUserAgent() ?? "", forHTTPHeaderField: ServerConstants.HttpHeaders.userAgent)
        request.setValue("Bearer \(token)", forHTTPHeaderField: ServerConstants.HttpHeaders.authorization)
        do {
            let (data, response) = try await urlConnection.send(request: request)
            guard let data, let http = response as? HTTPURLResponse, http.statusCode == ServerConstants.HttpConstants.ok else {
                FileLog.shared.addMessage("SocialAvatarUploadSender: non-OK status")
                return .failed
            }
            guard let parsed = try? Api_AvatarUploadResponse(serializedBytes: data) else {
                return .failed
            }
            return SocialAvatarUploadResult(parsed)
        } catch {
            FileLog.shared.addMessage("SocialAvatarUploadSender: POST failed: \(error)")
            return .failed
        }
    }

    /// Removes the current avatar. The backend invalidates the previous
    /// capability URL and cleans the private object through its outbox worker.
    public func remove() async -> Bool {
        guard SyncManager.isUserLoggedIn(), let token = await Self.bearerToken(),
              let url = URL(string: "\(ServerConstants.Urls.api())social/avatar")
        else {
            return false
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: ServerConstants.Timeouts.general)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: ServerConstants.HttpHeaders.authorization)
        request.setValue(ServerConfig.shared.syncDelegate?.privateUserAgent() ?? "", forHTTPHeaderField: ServerConstants.HttpHeaders.userAgent)

        do {
            let (_, response) = try await urlConnection.send(request: request)
            return (response as? HTTPURLResponse)?.statusCode == 204
        } catch {
            FileLog.shared.addMessage("SocialAvatarUploadSender: DELETE failed: \(error)")
            return false
        }
    }

    /// Bearer is required here (unlike the attribution-only transcript endpoints):
    /// a valid cached token, else one acquisition off the cooperative pool.
    private static func bearerToken() async -> String? {
        if let token = ServerSettings.validSyncingV2Token() {
            return token
        }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: TokenHelper.shared.acquireToken())
            }
        }
    }
}
