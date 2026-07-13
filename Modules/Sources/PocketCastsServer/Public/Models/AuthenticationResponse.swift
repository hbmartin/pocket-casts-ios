import Foundation

public struct AuthenticationResponse: Codable, Sendable {
    public let token: String?
    public let uuid: String?
    public let email: String?
    public let refreshToken: String?
    public let isNewAccount: Bool?
    /// Access-token TTL in seconds (`expires_in`). nil when the server didn't provide one,
    /// in which case token lifetime handling falls back to the 401-retry path.
    public let expiresIn: Int?
    /// Token type (`token_type`, e.g. "Bearer"). nil when the server didn't provide one.
    public let tokenType: String?

    internal init(token: String?, uuid: String?, email: String?, refreshToken: String?, isNewAccount: Bool?, expiresIn: Int?, tokenType: String?) {
        self.token = token
        self.uuid = uuid
        self.email = email
        self.refreshToken = refreshToken
        self.isNewAccount = isNewAccount
        self.expiresIn = expiresIn
        self.tokenType = tokenType
    }

    internal init(from apiResponse: Api_UserLoginResponse) {
        token = apiResponse.token.isEmpty ? nil : apiResponse.token
        uuid = apiResponse.uuid.isEmpty ? nil : apiResponse.uuid
        email = apiResponse.email.isEmpty ? nil : apiResponse.email
        // user/login doesn't issue refresh tokens or expiry yet. Once the M1 server
        // contract lands and the protobuf stubs are regenerated (`mise run generate:proto`),
        // map refresh_token/expires_in/token_type here the same way as Api_TokenLoginResponse.
        refreshToken = nil
        isNewAccount = false
        expiresIn = nil
        tokenType = nil
    }

    internal init(from apiResponse: Api_TokenLoginResponse) {
        token = apiResponse.accessToken.isEmpty ? nil : apiResponse.accessToken
        uuid = apiResponse.uuid.isEmpty ? nil : apiResponse.uuid
        email = apiResponse.email.isEmpty ? nil : apiResponse.email
        // Proto strings default to "" when the field is omitted — map that to nil so an
        // omitted refresh token can never clobber the one already stored in the Keychain.
        refreshToken = apiResponse.refreshToken.isEmpty ? nil : apiResponse.refreshToken
        isNewAccount = apiResponse.isNew
        expiresIn = apiResponse.expiresIn > 0 ? Int(apiResponse.expiresIn) : nil
        tokenType = apiResponse.tokenType.isEmpty ? nil : apiResponse.tokenType
    }

    internal init(from apiResponse: Api_RegisterResponse) {
        token = apiResponse.token.isEmpty ? nil : apiResponse.token
        uuid = apiResponse.uuid.isEmpty ? nil : apiResponse.uuid
        email = nil
        // user/register doesn't issue refresh tokens or expiry yet — see the
        // Api_UserLoginResponse initializer note about the M1 proto regeneration.
        refreshToken = nil
        isNewAccount = true
        expiresIn = nil
        tokenType = nil
    }
}
