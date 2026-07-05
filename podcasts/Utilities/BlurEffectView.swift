import PocketCastsUtils
import UIKit

class BlurEffectView: UIVisualEffectView {
    private let blurIntensity: Double
    private let animator: UIViewPropertyAnimator

    init(blurIntensity: Double) {
        self.blurIntensity = blurIntensity
        self.animator = UIViewPropertyAnimator(duration: 1, curve: .linear)
        super.init(effect: nil)
        animator.pausesOnCompletion = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        guard let superview else { return }
        backgroundColor = .clear
        frame = superview.bounds //Or setup constraints instead
        setupBlur()
    }

    private func setupBlur() {
        animator.stopAnimation(true)
        effect = nil

        animator.addAnimations { [weak self] in
            self?.effect = UIBlurEffect(style: .dark)
        }
        animator.fractionComplete = blurIntensity
    }

    deinit {
        // Stop on the main actor; the box keeps the animator alive until then
        let boxed = PocketCastsUtils.UncheckedSendable(animator)
        Task { @MainActor in
            boxed.value.stopAnimation(true)
        }
    }
}
