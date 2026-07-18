import Foundation
import PocketCastsServer
import PocketCastsUtils
import PocketCastsDataModel
import SafariServices

extension NowPlayingPlayerItemViewController {
    func addObservers() {
        addCustomObserver(PlaybackProgressed.self) { [weak self] _ in
            self?.progressUpdated()
        }
        addCustomObserver(EpisodeDurationChanged.self) { [weak self] _ in
            self?.progressUpdated()
        }
        addCustomObserver(PlaybackStarted.self) { [weak self] _ in
            self?.update(animatingArtwork: true, errorRelevant: true)
        }
        addCustomObserver(PlaybackPaused.self) { [weak self] _ in
            self?.update(animatingArtwork: true, errorRelevant: true)
        }
        addCustomObserver(PlaybackTrackChanged.self) { [weak self] _ in
            self?.playbackTrackChanged()
        }
        addCustomObserver(VideoPlaybackEngineSwitched.self) { [weak self] _ in
            self?.videoPlaybackEngineSwitched()
        }
        addCustomObserver(PodcastChaptersDidUpdate.self) { [weak self] _ in
            self?.update()
        }
        addCustomObserver(PlaybackEffectsChanged.self) { [weak self] _ in
            self?.update()
        }
        addCustomObserver(EpisodeEmbeddedArtworkLoaded.self) { [weak self] _ in
            self?.update()
        }
        addCustomObserver(PodcastChapterChanged.self) { [weak self] _ in
            self?.updateChapterInfo()
        }
        addCustomObserver(EpisodeDownloaded.self) { [weak self] _ in
            self?.update()
        }
        addCustomObserver(UIApplication.WillEnterForegroundMessage.self) { [weak self] _ in
            self?.update()
        }
        addCustomObserver(PlaybackFailed.self) { [weak self] _ in
            self?.update(errorRelevant: true)
        }

        addCustomObserver(SleepTimerChanged.self) { [weak self] _ in
            self?.sleepTimerUpdated()
        }
        addCustomObserver(PlayerActionsUpdated.self) { [weak self] _ in
            self?.reloadShelfActions()
        }
        #if !APPCLIP
        addCustomObserver(EpisodeStarredChanged.self) { [weak self] _ in
            self?.reloadShelfActions()
        }
        addCustomObserver(EpisodeDownloadStatusChanged.self) { [weak self] _ in
            self?.reloadShelfActions()
        }
        #endif
    }

    private func playbackTrackChanged() {
        floatingVideoView.isHidden = true
        update()
    }

    private func videoPlaybackEngineSwitched() {
        floatingVideoView.player = PlaybackManager.shared.internalPlayerForVideoPlayback()
    }

    /// - Parameters:
    ///   - animatingArtwork: `true` for play/pause events, whose artwork
    ///     shrink/dim change should animate rather than snap.
    ///   - errorRelevant: `true` for events that can change the active
    ///     playback error (start/pause/failure), so the error banner updates.
    func update(animatingArtwork: Bool = false, errorRelevant: Bool = false) {
        guard let playingEpisode = PlaybackManager.shared.currentEpisode() else { return }

        refreshMomentPins(for: playingEpisode)

        if playingEpisode.videoPodcast() {
            if floatingVideoView.isHidden {
                floatingVideoView.isHidden = false
                floatingVideoView.player = PlaybackManager.shared.internalPlayerForVideoPlayback()
                episodeImage.alpha = CGFloat.leastNonzeroMagnitude
            }
        } else {
            floatingVideoView.player = nil
            floatingVideoView.isHidden = true
            episodeImage.alpha = 1.0
        }

        let skipBackAmount = Settings.skipBackTime
        skipBackBtn.skipAmount = skipBackAmount

        let skipFwdAmount = Settings.skipForwardTime
        skipFwdBtn.skipAmount = skipFwdAmount

        updatePlayPauseButton(isPlaying: PlaybackManager.shared.playing())
        updateArtworkState(animated: animatingArtwork)
        updateUpTo(upTo: PlaybackManager.shared.currentTime(), duration: PlaybackManager.shared.duration(), moveSlider: true)
        reloadShelfActions()
        updateChaptersControls()
        updateChapterInfo()
        updateChapterProgress()
        updateColors()
        if errorRelevant {
            updateError()
        }
        if !showingCustomImage {
            ImageManager.sharedManager.loadImage(episode: playingEpisode, imageView: episodeImage, size: .page)
        }
    }

    private func updateColors() {
        let backgroundColor = PlayerColorHelper.playerBackgroundColor01()
        view.backgroundColor = backgroundColor
        playPauseBtn.playButtonColor = backgroundColor

        let buttonColor = ThemeColor.playerContrast01()
        playPauseBtn.circleColor = buttonColor
        skipBackBtn.tintColor = buttonColor
        skipFwdBtn.tintColor = buttonColor

        let highlightColor = PlayerColorHelper.playerHighlightColor01(for: .dark)
        timeSlider.leftColor = highlightColor
        timeSlider.animationColor = PlayerColorHelper.playerHighlightColor01(for: .dark).withAlphaComponent(0.2)
        timeSlider.circleColor = buttonColor
        timeSlider.rightColor = ThemeColor.playerContrast06()
        timeSlider.popupColor = ThemeColor.playerContrast06()
        timeSlider.popupTextColor = ThemeColor.playerContrast01()

        updateShelfGlass()
    }

    func updatePlayPauseButton(isPlaying: Bool) {
        playPauseBtn.isPlaying = isPlaying
    }

    /// Apple-Music-style paused state: the artwork rests slightly shrunken and
    /// dimmed while paused, so playback state is readable at a glance.
    func updateArtworkState(animated: Bool) {
        if artworkDimView.superview == nil {
            episodeImage.addSubview(artworkDimView)
            NSLayoutConstraint.activate([
                artworkDimView.leadingAnchor.constraint(equalTo: episodeImage.leadingAnchor),
                artworkDimView.trailingAnchor.constraint(equalTo: episodeImage.trailingAnchor),
                artworkDimView.topAnchor.constraint(equalTo: episodeImage.topAnchor),
                artworkDimView.bottomAnchor.constraint(equalTo: episodeImage.bottomAnchor)
            ])
        }

        // The floating video view owns this space for video episodes.
        let isVideo = PlaybackManager.shared.currentEpisode()?.videoPodcast() ?? false
        let playing = PlaybackManager.shared.playing()
        // Reduce Motion: crossfade the dim only, never scale.
        let shouldShrink = !playing && !isVideo && !UIAccessibility.isReduceMotionEnabled
        let targetTransform = shouldShrink ? CGAffineTransform(scaleX: 0.8, y: 0.8) : .identity
        let targetDim: CGFloat = (playing || isVideo) ? 0 : 0.2

        let changes = {
            self.episodeImage.transform = targetTransform
            self.artworkDimView.alpha = targetDim
        }

        guard animated else {
            changes()
            return
        }

        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 1, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
    }

    func updateChapterInfo() {
        updateChapterInfoWithChapters(PlaybackManager.shared.currentChapters())
    }

    private func updateChapterInfoForTime(_ time: TimeInterval) {
        updateChapterInfoWithChapters(PlaybackManager.shared.chaptersForTime(time: time))
    }

    private func updateChapterInfoWithChapters(_ chapters: Chapters) {
        guard let playingEpisode = PlaybackManager.shared.currentEpisode() else { return }
        if let visibleChapter = chapters.visibleChapter, PlaybackManager.shared.chapterCount() != 0 {
            episodeInfoView.isHidden = true
            chapterInfoView.isHidden = false

            chapterName.text = !chapters.title.isEmpty ? chapters.title : playingEpisode.displayableTitle()

            chapterSkipBackBtn.isEnabled = !visibleChapter.isFirst
            chapterSkipFwdBtn.isEnabled = !visibleChapter.isLast
            chapterCounter.text = L10n.playerChapterCount((visibleChapter.index + 1).localized(), PlaybackManager.shared.chapterCount().localized())

            if let artwork = chapters.artwork {
                showingCustomImage = true
                episodeImage.image = artwork
                episodeImage.accessibilityLabel = L10n.playerArtwork(chapterName.text ?? "")
            } else if showingCustomImage {
                showingCustomImage = false
                ImageManager.sharedManager.loadImage(episode: playingEpisode, imageView: episodeImage, size: .page)
                episodeImage.accessibilityLabel = L10n.playerArtwork(playingEpisode.title ?? "")
            }
            chapterLink.isHidden = chapters.url == nil
        } else {
            episodeInfoView.isHidden = false
            chapterInfoView.isHidden = true
            episodeName.text = playingEpisode.displayableTitle()
            podcastName.text = playingEpisode.subTitle()
            showingCustomImage = false
            chapterLink.isHidden = true
        }
    }

    private func updateChapterProgress(for chapter: ChapterInfo?, playheadPosition: TimeInterval) {
        guard let chapter else {
            return
        }

        let remainingTime = chapter.duration + chapter.startTime.seconds - playheadPosition
        chapterTimeLeftLabel.text = TimeFormatter.shared.singleUnitFormattedShortestTime(time: remainingTime)
        let percentageCompleted = 1 - (remainingTime / chapter.duration)
        chapterProgress.startingAngle = CGFloat((percentageCompleted * 360) - 90)
    }

    func updateChapterProgress() {
        updateChapterProgress(for: PlaybackManager.shared.currentChapters().visibleChapter, playheadPosition: PlaybackManager.shared.currentTime())
    }

    private func updateTimeLabels(upTo: TimeInterval, remaining: TimeInterval) {
        timeElapsed.text = TimeFormatter.shared.playTimeFormat(time: upTo)
        timeRemaining.text = "-\(TimeFormatter.shared.playTimeFormat(time: remaining))"
    }

    func updateUpTo(upTo: TimeInterval, duration: TimeInterval, moveSlider: Bool) {
        let remaining = max(0, duration - upTo)
        updateTimeLabels(upTo: upTo, remaining: remaining)
        updateChapterInfoWithChapters(PlaybackManager.shared.chaptersForTime(time: upTo))

        if moveSlider {
            timeSlider.totalDuration = duration

            timeSlider.currentTime = upTo
        }

        timeSlider.indeterminant = PlaybackManager.shared.buffering() && PlaybackManager.shared.playing()
    }

    var isErrorVisible: Bool {
        return errorBottomSpacing.constant == 0
    }

    func updateError() {
        guard PlaybackManager.shared.currentEpisode() != nil,
              let error = PlaybackManager.shared.activeError else {
            hideError()
            return
        }
        if !isErrorVisible {
            showError(error, dismissAfter: 5)
        }
    }

    func showError(_ error: PlaybackManager.PlaybackError, dismissAfter seconds: TimeInterval?) {
        AnalyticsPlaybackHelper.shared.playbackErrorShown(playerSource: .fullPlayer)
        // Move error container in view
        errorLabel.attributedText = error.shortUserAttributedMessage(mainColor: ThemeColor.playerContrast02(), interactiveColor: ThemeColor.primaryInteractive01())
        errorContainer.layoutIfNeeded()
        errorBottomSpacing.constant = 0
        playerBottomSpacing.constant = 16
        UIView.animate(withDuration: 0.3,
                       delay: 0,
                       options: .curveEaseInOut) {
            [weak self] in
            self?.view.layoutIfNeeded()
        }

        errorAutoDismissWork?.cancel()
        if let seconds {
            let work = DispatchWorkItem { [weak self] in self?.hideError() }
            errorAutoDismissWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
    }

    func hideError() {
        // Move error out
        errorBottomSpacing.constant = -48
        playerBottomSpacing.constant = 30
        UIView.animate(withDuration: 0.3,
                       delay: 0,
                       options: .curveEaseInOut) {
            [weak self] in
            self?.view.layoutIfNeeded()
        }
    }

    @objc func errorTapped() {
        guard let error  = PlaybackManager.shared.activeError,
              let url = error.userAction
        else {
            return
        }
        AnalyticsPlaybackHelper.shared.playbackErrorTapped(playerSource: .fullPlayer)
        #if !APPCLIP
        URLHelper.open(url, context: .trustedDocumentation, options: .init(presenter: self, modalPresentationStyle: .formSheet))
        #endif
    }

    func updateProvisionalChapterInfoForTime(time: TimeInterval) {
        guard let playingEpisode = PlaybackManager.shared.currentEpisode() else { return }

        if PlaybackManager.shared.chapterCount() == 0 {
            return
        }
        let chapters = PlaybackManager.shared.chaptersForTime(time: time)
        // swiftlint:disable:next empty_count
        if chapters.count > 0 {
            episodeName.text = !chapters.title.isEmpty ? chapters.title : playingEpisode.displayableTitle()
            updateChapterProgress(for: chapters.visibleChapter, playheadPosition: time)
            updateUpTo(upTo: time, duration: chapters.duration, moveSlider: false)
            chapterCounter.text = L10n.playerChapterCount((chapters.index + 1).localized(), PlaybackManager.shared.chapterCount().localized())
        }
    }

    private func updateChaptersControls() {
        if PlaybackManager.shared.chapterCount() > 0 {
            chapterSkipBackBtn.isHidden = false
            chapterSkipFwdBtn.isHidden = false
            chapterCounter.isHidden = false
            chapterTimeLeftLabel.isHidden = false
        } else {
            chapterSkipBackBtn.isHidden = true
            chapterSkipFwdBtn.isHidden = true
            chapterCounter.isHidden = true
            chapterTimeLeftLabel.isHidden = true
        }
    }

    // MARK: - Progress

    func progressUpdated() {
        if timeSlider.isScrubbing() || PlaybackManager.shared.isSeeking() { return }

        updateUpTo(upTo: PlaybackManager.shared.currentTime(), duration: PlaybackManager.shared.duration(), moveSlider: true)

        if !chapterSkipFwdBtn.isHidden {
            updateChapterProgress()
        }
    }
}
