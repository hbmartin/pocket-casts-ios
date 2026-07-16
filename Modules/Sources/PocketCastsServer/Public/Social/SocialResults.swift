import Foundation

/// Result of a handle availability check / claim attempt — the public mirror of
/// the wire `Api_HandleStatus`. `.unknown` covers transport failure and any
/// unrecognized status. `.taken`/`.reserved`/`.tombstoned`/`.invalid` are all
/// "can't have this handle" for the UI, but distinguished so it can explain why.
public enum SocialHandleAvailability: Equatable, Sendable {
    case available
    case taken
    case reserved
    case tombstoned
    case invalid
    case unknown

    /// Whether the handle can be claimed.
    public var isClaimable: Bool { self == .available }
}

/// Why a user or content item is being reported — the public mirror of the wire
/// `Api_ReportReason`.
public enum SocialReportReason: Int, Sendable, CaseIterable {
    case spam = 1
    case harassment = 2
    case hate = 3
    case sexual = 4
    case impersonation = 5
    case other = 6
}

/// Outcome of an avatar upload after the mandatory CSAM/nudity scan. `.failed`
/// is transport failure; the rejection cases are the server's scan verdict.
public enum SocialAvatarUploadResult: Equatable, Sendable {
    case accepted(avatarURL: String)
    case rejectedScan
    case rejectedFormat
    case failed
}

// MARK: - Wire mapping (internal: the Api_* types are module-internal)

extension SocialHandleAvailability {
    init(_ api: Api_HandleStatus) {
        switch api {
        case .available: self = .available
        case .taken: self = .taken
        case .reserved: self = .reserved
        case .tombstoned: self = .tombstoned
        case .invalid: self = .invalid
        case .unspecified, .UNRECOGNIZED: self = .unknown
        }
    }
}

extension SocialReportReason {
    var apiValue: Api_ReportReason {
        switch self {
        case .spam: return .spam
        case .harassment: return .harassment
        case .hate: return .hate
        case .sexual: return .sexual
        case .impersonation: return .impersonation
        case .other: return .other
        }
    }
}

extension SocialAvatarUploadResult {
    init(_ api: Api_AvatarUploadResponse) {
        switch api.status {
        case .accepted: self = .accepted(avatarURL: api.avatarURL)
        case .rejectedScan: self = .rejectedScan
        case .rejectedFormat: self = .rejectedFormat
        case .unspecified, .UNRECOGNIZED: self = .failed
        }
    }
}
