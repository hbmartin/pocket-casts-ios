import UIKit

extension ProfileViewController: PromotionRedeemedDelegate {
    func showPromotionViewController(promoCode: String?) {
        // Promo codes are obsolete now that every feature is unlocked.
    }

    func showPromotionRedeemedAcknowledgement() {
        // Promo codes are obsolete now that every feature is unlocked.
    }

    func promotionRedeemed(message: String) {
        promoRedeemedMessage = message
    }
}
