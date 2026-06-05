import SwiftUI
import PocketCastsServer

/// View model for the header view that appears on the Profile tab view
class AccountHeaderViewModel: ProfileDataViewModel {
    @Published var viewState: ViewState = .freeAccount

    override func update() {
        super.update()

        guard SubscriptionHelper.hasActiveSubscription() else {
            viewState = .freeAccount
            return
        }

        let expirationDate = SubscriptionHelper.subscriptionRenewalDate()
        let frequency = SubscriptionHelper.subscriptionFrequencyValue()
        let type = SubscriptionHelper.subscriptionType()
        let giftDays = SubscriptionHelper.subscriptionGiftDays()

        let hasLifetime = SubscriptionHelper.hasLifetimeGift()
        let hasRenewing = SubscriptionHelper.hasRenewingSubscription()
        let platform = SubscriptionHelper.subscriptionPlatform()

        switch (hasRenewing, platform, hasLifetime) {
        case (true, _, _):
            viewState = .activeSubscription(type, frequency, expirationDate)
        case (false, .gift, true):
            viewState = .lifetime
        case (false, .gift, false):
            viewState = .freeTrial(Double(giftDays).days)
        default:
            viewState = .paymentCancelled(type, frequency)
        }
    }

    enum ViewState {
        case freeAccount
        case lifetime
        case activeSubscription(SubscriptionType, SubscriptionFrequency, Date?)
        case freeTrial(TimeInterval)
        case paymentCancelled(SubscriptionType, SubscriptionFrequency)
    }
}
