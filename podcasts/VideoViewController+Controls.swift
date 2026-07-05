
extension VideoViewController {
    private static let controlHideTime = 3.seconds

    @objc func videoViewTapped() {
        if controlsDisabled { return }

        toggleVideoControls()
    }

    @objc func videoViewDoubleTapped() {
        if controlsDisabled { return }

        toggleFillScreen()
    }

    // MARK: - Timer

    func startHideControlsTimer() {
        if controlsDisabled { return }

        stopHideControlsTimer()

        let timer = Timer(timeInterval: VideoViewController.controlHideTime, repeats: false, block: { [weak self] _ in
            // Scheduled on the main run loop below, so the callback is main-actor
            MainActor.assumeIsolated {
                self?.hideVideoControls()
            }
        })
        RunLoop.main.add(timer, forMode: .common)
        showHideTimer = timer
    }

    func stopHideControlsTimer() {
        showHideTimer?.invalidate()
    }

    // MARK: - Hide Show

    func disableControls() {
        controlsDisabled = true
        hideVideoControls()
    }

    func enableControls() {
        controlsDisabled = false
        showVideoControls()
    }

    private func toggleVideoControls() {
        if controlsShowing {
            hideVideoControls()
        } else {
            showVideoControls()
            if PlaybackManager.shared.playing() { startHideControlsTimer() }
        }
    }

    private func hideVideoControls() {
        controlsShowing = false
        UIView.animate(withDuration: Constants.Animation.defaultAnimationTime) { [weak self] in
            self?.controlsOverlay.alpha = 0
        }
    }

    private func showVideoControls() {
        controlsShowing = true
        UIView.animate(withDuration: Constants.Animation.defaultAnimationTime) { [weak self] in
            self?.controlsOverlay.alpha = 1
        }
    }
}
