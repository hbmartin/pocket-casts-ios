import Foundation
import PocketCastsServer

/// Abstraction to return information about the subscriptions
protocol TracksSubscriptionData {
    func hasActiveSubscription() -> Bool
    func hasLifetimeGift() -> Bool
}

/// Retrieves Pocket Casts specific data for use in tracks
struct PocketCastsTracksSubscriptionData: TracksSubscriptionData {
    func hasActiveSubscription() -> Bool {
        true
    }

    func hasLifetimeGift() -> Bool {
        false
    }
}
