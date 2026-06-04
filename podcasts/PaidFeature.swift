import Combine
import PocketCastsServer
import PocketCastsUtils
import SwiftUI

// MARK: - Features

extension PaidFeature {
    static var bookmarks: PaidFeature = .plusFeature
    static var deselectChapters: PaidFeature = .plusFeature
    static var slumber: PaidFeature = .plusFeature
}

/// A `PaidFeature` represents a feature that is unlocked with a subscription tier, and is considered to be unlocked if the tier
/// is equal to or higher than the set `tier` value.
///
/// The unlock state is self managed by listening for relevant notifications and updating the `isUnlocked` property accordingly.
///
/// Since this is a subclass of `ObservableObject` it can easily be used in SwiftUI. Outside SwiftUI, you can use the `objectWillChange`
/// publisher to be notified about changes.
///
/// And while the class is an `ObservableObject` it doesn't use any `@Published` properties and instead manually triggers `objectWillChange`.
/// This is done to ensure future compatibility of any property changes by not allowing listeners to directly access a published properties publisher.
///
// MARK: - Features

extension PaidFeature {
    static var bookmarks: PaidFeature = .plusFeature
    static var deselectChapters: PaidFeature = .plusFeature
    static var slumber: PaidFeature = .plusFeature
}

class PaidFeature: ObservableObject {
    /// Whether the feature is unlocked for the active subscription tier
    var isUnlocked: Bool {
        true
    }

    /// The minimum subscription level required to unlock this feature
    let tier: SubscriptionTier

    /// Whether the feature is in its early access period or not.
    let inEarlyAccess: Bool

    /// Creates a new paid feature with a minimum tier
    init(tier: SubscriptionTier,
         betaTier: SubscriptionTier? = nil,
         inEarlyAccess: Bool = false) {
        self.tier = tier
        self.inEarlyAccess = inEarlyAccess
    }
}

// MARK: - Private: Feature State Helpers

private extension PaidFeature {
    static var inEarlyAccess: PaidFeature {
        .init(tier: .patron, inEarlyAccess: true)
    }

    static var patronFeature: PaidFeature {
        .init(tier: .patron)
    }

    static var plusFeature: PaidFeature {
        .init(tier: .plus)
    }
}
