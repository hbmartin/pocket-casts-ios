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
        refreshToken = apiResponse.refreshToken.isEmpty ? nil : apiResponse.refreshToken
        isNewAccount = false
        expiresIn = apiResponse.expiresIn > 0 ? Int(apiResponse.expiresIn) : nil
        tokenType = "Bearer"
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
        refreshToken = apiResponse.refreshToken.isEmpty ? nil : apiResponse.refreshToken
        isNewAccount = true
        expiresIn = apiResponse.expiresIn > 0 ? Int(apiResponse.expiresIn) : nil
        tokenType = "Bearer"
    }
}
