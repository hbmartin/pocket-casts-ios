import Foundation
import PocketCastsDataModel
import PocketCastsUtils

import AuthenticationServices

public extension ASAuthorizationAppleIDProvider.CredentialState {
    var loggingValue: String {
        switch self {
        case .revoked:
            return "revoked (\(rawValue))"
        case .authorized:
            return "authorized (\(rawValue))"
        case .notFound:
            return "notFound (\(rawValue))"
        case .transferred:
            return "transferred (\(rawValue))"
        default:
            return "unknown raw value: \(rawValue)}"
        }
    }
}

public enum AuthenticationScope: String {
    case mobile
    case tv
    case sonos
}

public extension ApiServerHandler {
    func validateLogin(identityToken: String?, scope: AuthenticationScope = .mobile) async throws -> AuthenticationResponse {
        guard let identityToken,
              let request = tokenRequest(identityToken: identityToken, scope: scope)
        else {
            FileLog.shared.addMessage("Unable to create protobuffer request to obtain token via Apple SSO")
            throw APIError.UNKNOWN
        }

        return try await obtainToken(request: request, usingRefreshToken: true)
    }

    func refreshIdentityToken() async throws -> AuthenticationResponse {
        guard
            let identityToken = try ServerSettings.refreshToken(),
            let request = tokenRequest(identityToken: identityToken, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30.seconds)
        else {
            FileLog.shared.addMessage("Unable to locate Apple SSO token in Keychain")
            throw APIError.TOKEN_DEAUTH
        }

        return try await obtainToken(request: request, usingRefreshToken: true)
    }

    private func tokenRequest(identityToken: String?, cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy, timeoutInterval: TimeInterval = 15.seconds, scope: AuthenticationScope = .mobile) -> URLRequest? {
        guard let identityToken else {
            return nil
        }

        let url = ServerHelper.asUrl(ServerConstants.Urls.api() + "user/token")

        var data = Api_UserTokenRequest()
        data.refreshToken = identityToken
        data.grantType = "refresh_token"
        data.scope = scope.rawValue

        return ServerHelper.createProtoRequest(url: url, data: try! data.serializedData())
    }
}
