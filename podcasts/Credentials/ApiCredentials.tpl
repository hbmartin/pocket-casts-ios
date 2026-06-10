/// API Credentials. Generated on %{timestamp}
///
struct ApiCredentials {

    /// Encrypted Logging Public Key
    ///
    static let loggingEncryptionKey = "%{encrypted_log_key}"

    /// Sharing Server Secret
    ///
    static let sharingServerSecret = "%{sharing_server_secret}"

    /// Bitdrift SDK Key
    ///
    static let bitdriftSDKKey = "%{bitdrift_sdk_key}"

    /// TelemetryDeck App ID
    ///
    static let telemetryDeckAppID = "%{telemetry_deck_app_id}"
}
