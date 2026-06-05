import Foundation
import PocketCastsUtils

open class SubscriptionHelper: NSObject {
    public static let shared = SubscriptionHelper()

    public static var hasCancelledSubscription: Bool {
        false
    }

    open var activeTier: SubscriptionTier {
        Self.activeTier
    }

    public static var activeSubscriptionType: SubscriptionType {
        .none
    }

    public static var activeTier: SubscriptionTier {
        .none
    }

    public class var subscriptionTier: SubscriptionTier {
        get { .none }
        set { }
    }

    public class func hasActiveSubscription() -> Bool {
        false
    }

    public class func hasRenewingSubscription() -> Bool {
        false
    }

    public class func subscriptionGiftDays() -> Int {
        0
    }

    public class func subscriptionPlatform() -> SubscriptionPlatform {
        .none
    }

    public class func subscriptionRenewalDate() -> Date? {
        nil
    }

    public class func subscriptionCreateDate() -> Date? {
        nil
    }

    public class func timeToSubscriptionExpiry() -> TimeInterval? {
        nil
    }

    public class func hasLifetimeGift() -> Bool {
        false
    }

    public class func subscriptionFrequencyValue() -> SubscriptionFrequency {
        .none
    }

    public class func setSubscriptionPaid(_ value: Int) { }
    public class func setSubscriptionPlatform(_ value: Int) { }
    public class func setSubscriptionAutoRenewing(_ value: Bool) { }
    public class func setSubscriptionExpiryDate(_ value: TimeInterval) { }
    public class func setSubscriptionCreateDate(_ value: TimeInterval) { }
    public class func setSubscriptionGiftDays(_ value: Int) { }
    public class func setSubscriptionFrequency(_ value: Int) { }
    public class func setSubscriptionType(_ value: Int) { }

    public class func setSubscriptionGiftAcknowledgement(_ value: Bool) {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.freeGiftAcknowledgement = value
        }
        UserDefaults.standard.set(value, forKey: ServerConstants.UserDefaults.subscriptionGiftAcknowledgement)
        UserDefaults.standard.set(true, forKey: ServerConstants.UserDefaults.subscriptionGiftAcknowledgementNeedsSyncKey)
    }

    public class func subscriptionGiftAcknowledgement() -> Bool {
        if FeatureFlag.newSettingsStorage.enabled {
            return SettingsStore.appSettings.freeGiftAcknowledgement
        }
        return UserDefaults.standard.bool(forKey: ServerConstants.UserDefaults.subscriptionGiftAcknowledgement)
    }

    public class func subscriptionGiftAcknowledgementNeedsSyncing() -> Bool {
        UserDefaults.standard.bool(forKey: ServerConstants.UserDefaults.subscriptionGiftAcknowledgementNeedsSyncKey)
    }

    public class func subscriptionGiftAcknowledgementSynced() {
        UserDefaults.standard.set(false, forKey: ServerConstants.UserDefaults.subscriptionGiftAcknowledgementNeedsSyncKey)
    }

    public class func subscriptionType() -> SubscriptionType {
        .none
    }

    public class func setSubscriptionPodcasts(_ value: [PodcastSubscription]) { }

    public class func subscriptionPodcasts() -> [PodcastSubscription]? {
        nil
    }

    public class func subscriptionForPodcast(uuid: String) -> PodcastSubscription? {
        nil
    }

    public class func numActiveSubscriptionBundles() -> Int {
        0
    }

    public class func subscriptionBundles() -> [BundleSubscription]? {
        nil
    }

    public class func bundleSubscriptionForPodcast(podcastUuid: String) -> BundleSubscription? {
        nil
    }

    public class var shouldRemoveBannerAd: Bool {
        get { true }
        set { }
    }

    public class var shouldRemoveDiscoverAds: Bool {
        get { true }
        set { }
    }

    public class var shouldDisplayBannerAd: Bool {
        false
    }

    public class var shouldDisplayPlayerBannerAd: Bool {
        false
    }
}
