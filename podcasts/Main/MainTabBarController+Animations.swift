import PocketCastsDataModel
import PocketCastsUtils
import UIKit

// MARK: - Up Next "genie" add animation

extension MainTabBarController {
    static let upNextGenieViewTag = 776_611

    func animateEpisodeAddedToUpNext(_ message: UpNextEpisodeAdded) {
        guard let episodeUuid = message.uuid else {
            // Nothing to animate — just keep the count current.
            upNextQueueDidChange()
            return
        }

        // Whether this was a "Play Next" (top) or "Play Last" (bottom) add, so
        // the flying badge can show the matching glyph and tint.
        let toTop = message.addedToTop

        Task { [weak self] in
            let episode = await DataManager.sharedManager.findBaseEpisodeAsync(uuid: episodeUuid)
            guard let self else { return }
            if let episode {
                playUpNextAddedGenieAnimation(for: episode, toTop: toTop)
            } else {
                upNextQueueDidChange()
            }
        }
    }

    func playUpNextAddedGenieAnimation(for episode: BaseEpisode, toTop: Bool) {
        // Fly the artwork into the queue's on-screen representation: the mini
        // player's now-playing artwork. Skip the animation (and just keep the
        // count current) when it isn't on screen or another genie is already
        // in flight.
        guard view.window != nil,
              view.viewWithTag(Self.upNextGenieViewTag) == nil,
              let targetFrame = upNextGenieTargetFrame() else {
            upNextQueueDidChange()
            return
        }

        let artworkSize: CGFloat = 64
        let cornerRadius: CGFloat = 14
        let target = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
        let start = CGPoint(x: target.x, y: targetFrame.minY - 24)

        let container = UIView(frame: CGRect(x: 0, y: 0, width: artworkSize, height: artworkSize))
        container.tag = Self.upNextGenieViewTag
        container.center = start
        container.isUserInteractionEnabled = false
        container.layer.cornerRadius = cornerRadius
        container.layer.cornerCurve = .continuous
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.3
        container.layer.shadowRadius = 12
        container.layer.shadowOffset = CGSize(width: 0, height: 6)

        // A plain image view, not `PodcastImageView`, which re-rounds its inner
        // image view with a circular curve and clobbers the continuous corner.
        let artwork = UIImageView(frame: container.bounds)
        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        artwork.layer.cornerRadius = cornerRadius
        artwork.layer.cornerCurve = .continuous
        artwork.layer.borderWidth = 1
        artwork.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        ImageManager.sharedManager.loadImage(episode: episode, imageView: artwork, size: .list)
        container.addSubview(artwork)

        // A circled "Play Next" / "Play Last" glyph perched on the top-right
        // corner so the flying artwork clearly reads as "being added" — and as
        // *which* add — rather than just a floating thumbnail.
        let badge = makeUpNextAddBadge(toTop: toTop, diameter: 26)
        badge.center = CGPoint(x: container.bounds.width - 5, y: 5)
        container.addSubview(badge)

        view.addSubview(container)

        // Phase 1: pop in, hovering just above the landing point.
        container.alpha = 0
        container.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.68, initialSpringVelocity: 0.5, options: [.allowUserInteraction, .curveEaseOut], animations: {
            container.alpha = 1
            container.transform = .identity
        }, completion: { _ in
            // Phase 2: genie-suck down into it along a curve.
            self.runUpNextGenieSuck(on: container, from: start, to: target)
        })
    }

    /// A circled badge showing the add that just happened — a white "Play Next"
    /// or "Play Last" glyph and ring over the matching swipe-action tint
    /// (`support04` for Play Next, `support03` for Play Last) — sized to perch on
    /// the top-right corner of the flying artwork.
    private func makeUpNextAddBadge(toTop: Bool, diameter: CGFloat) -> UIView {
        let badge = UIView(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        badge.backgroundColor = toTop ? ThemeColor.support04() : ThemeColor.support03()
        badge.layer.cornerRadius = diameter / 2
        badge.layer.borderWidth = 1.5
        badge.layer.borderColor = UIColor.white.cgColor

        let glyph = UIImage(named: toTop ? "list_playnext" : "list_playlast")?.withRenderingMode(.alwaysTemplate)
        let icon = UIImageView(image: glyph)
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        icon.frame = badge.bounds.insetBy(dx: diameter * 0.24, dy: diameter * 0.24)
        badge.addSubview(icon)
        return badge
    }

    func runUpNextGenieSuck(on container: UIView, from start: CGPoint, to target: CGPoint) {
        let duration: CFTimeInterval = 0.32

        let path = UIBezierPath()
        path.move(to: start)
        // A subtle sideways swoop that accelerates into the artwork, echoing
        // the macOS genie effect.
        let control = CGPoint(x: start.x + (target.x - start.x) * 0.5 - 28,
                              y: (start.y + target.y) / 2)
        path.addQuadCurve(to: target, controlPoint: control)

        let positionAnim = CAKeyframeAnimation(keyPath: "position")
        positionAnim.path = path.cgPath
        positionAnim.calculationMode = .cubicPaced

        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 1.0
        scaleAnim.toValue = 0.06

        let fadeAnim = CABasicAnimation(keyPath: "opacity")
        fadeAnim.fromValue = 1.0
        fadeAnim.toValue = 0.0
        fadeAnim.beginTime = duration * 0.55

        let group = CAAnimationGroup()
        group.animations = [positionAnim, scaleAnim, fadeAnim]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeIn)
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak container] in
            container?.removeFromSuperview()
        }
        container.layer.add(group, forKey: "upNextGenie")
        CATransaction.commit()

        // Near the end of the suck, swap in the new count so it reads as the artwork landing.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.8) { [weak self] in
            self?.upNextQueueDidChange()
        }
    }

    /// The frame the "added to Up Next" genie should fly into, in `view`'s
    /// coordinate space, or `nil` when no landing point is on screen.
    ///
    /// The mini player's now-playing artwork is the queue's only on-screen
    /// representation, whether the mini player is docked above the tab bar or
    /// riding in the iOS 26 collapsed pill as the bottom accessory.
    private func upNextGenieTargetFrame() -> CGRect? {
        guard let artwork = NavigationManager.sharedManager.miniPlayer?.podcastArtwork,
              artwork.window != nil else { return nil }
        let frame = artwork.superview?.convert(artwork.frame, to: view)

        guard let frame, !frame.isNull, frame.width > 0, frame.height > 0,
              view.bounds.contains(CGPoint(x: frame.midX, y: frame.midY)) else {
            return nil
        }
        return frame
    }

    /// A quick spring "pop" on the mini player artwork — the queue's on-screen
    /// representation — so a queue change is felt, not just silently re-rendered.
    func pulseUpNextTarget() {
        // A burst of rapid adds shouldn't stack overlapping springs — one pop
        // already conveys "queue grew".
        guard !isPulsingUpNextTarget else { return }

        guard let artwork = NavigationManager.sharedManager.miniPlayer?.podcastArtwork,
              artwork.window != nil else { return }

        isPulsingUpNextTarget = true
        Self.playUpNextPopAnimation(on: [artwork]) { [weak self] in
            self?.isPulsingUpNextTarget = false
        }
    }

    /// A snappy, bounce-free grow, then a single softly springy settle. The
    /// grow is short enough that the peak isn't visibly held, and one gentle
    /// bounce on the way back reads as lively rather than jittery.
    static func playUpNextPopAnimation(on views: [UIView], completion: (() -> Void)? = nil) {
        UIView.animate(springDuration: 0.15, bounce: 0, initialSpringVelocity: 0,
                       options: [.allowUserInteraction]) {
            views.forEach { $0.transform = CGAffineTransform(scaleX: 1.15, y: 1.15) }
        } completion: { _ in
            UIView.animate(springDuration: 0.45, bounce: 0.28, initialSpringVelocity: 0,
                           options: [.allowUserInteraction]) {
                views.forEach { $0.transform = .identity }
            } completion: { _ in
                completion?()
            }
        }
    }
}
