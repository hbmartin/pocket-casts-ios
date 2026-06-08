final class RemovedLegacyPaymentReferences {
    func legacyPurchaseAnalytics() {
        // ruleid: pocketcasts.no-legacy-plus-payment-entry-points
        AnalyticsHelper.plusPlanPurchased()
    }

    // ruleid: pocketcasts.no-legacy-plus-payment-entry-points
    let legacyNotification = ServerNotifications.iapPurchaseCompleted

    // ruleid: pocketcasts.no-legacy-plus-payment-entry-points
    let legacyTask = CancelSubscriptionTask(bundleUuid: "bundle")

    // ruleid: pocketcasts.no-legacy-plus-payment-entry-points
    let legacyFlag = FeatureFlag.newOfferEligibilityCheck

    // ruleid: pocketcasts.no-legacy-plus-payment-entry-points
    let legacySource = PlusUpgradeViewSource.profile

    // ruleid: pocketcasts.no-legacy-plus-payment-entry-points
    let promo = RedeemPromoCodeTask(promoCode: "PLUS")

    // ruleid: pocketcasts.no-legacy-plus-payment-entry-points
    let legacyDebugIap = Settings.shouldEnableIAPInTestFlightBuilds

    // ruleid: pocketcasts.no-legacy-plus-payment-entry-points
    let legacyImage = AppTheme.paymentFailedImageName()

    // ok: pocketcasts.no-legacy-plus-payment-entry-points
    let paidPodcastSubscription = "supporter podcast subscription"
}
