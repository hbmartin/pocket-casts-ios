import Foundation

/// The six social push kinds (Slice 8, docs/Social.md). Raw values mirror the
/// wire enum; the profile's `socialPushDisabled` bitmask stores bit
/// `rawValue - 1` set when a type is switched OFF (default 0 = all on).
public enum SocialPushType: Int, Sendable, CaseIterable {
    case followRequest = 1
    case followApproved = 2
    case newFollower = 3
    case sharedItem = 4
    case commentReply = 5
    case listInvite = 6
    case groupInvite = 7
    case groupPost = 8

    public var bit: Int64 { 1 << Int64(rawValue - 1) }

    public static func isEnabled(_ type: SocialPushType, in disabledMask: Int64) -> Bool {
        disabledMask & type.bit == 0
    }

    public static func setEnabled(_ type: SocialPushType, enabled: Bool, in disabledMask: Int64) -> Int64 {
        enabled ? disabledMask & ~type.bit : disabledMask | type.bit
    }
}
