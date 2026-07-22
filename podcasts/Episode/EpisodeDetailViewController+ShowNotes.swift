import Foundation
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils
import SafariServices
import WebKit

nonisolated private struct EpisodeMentionsCardPayload: Sendable {
    let mentions: [EntityMention]
    let usedModel: Bool
}

/// The transcript index and entity cache are synchronous database/disk APIs.
/// `@concurrent` ensures those reads do not inherit the caller's MainActor.
@concurrent
private func episodeMentionsCardPayload(episodeUuid: String) async -> EpisodeMentionsCardPayload? {
    let search = DataManager.sharedManager.transcriptSearch
    guard search.isAvailable else { return nil }

    var segments = search.segments(episodeUuid: episodeUuid, source: .generated)
    var source = PocketCastsDataModel.TranscriptSource.generated
    if segments.isEmpty {
        segments = search.segments(episodeUuid: episodeUuid, source: .provided)
        source = .provided
    }
    guard !segments.isEmpty, !Task.isCancelled else { return nil }

    // Ties the cache to the exact indexed transcript: a re-index changes the
    // count or tail time and reads as a miss.
    let tailStartBitPattern = (segments.last?.startTime ?? 0).bitPattern
    let fingerprint = "\(source.rawValue)-\(segments.count)-\(tailStartBitPattern)"

    let intelligence = OnDeviceIntelligence.shared
    let usedModel: Bool = {
        if case .available = intelligence.availability() { return true }
        return false
    }()
    let mentions = await EntityMentionGenerator().mentions(
        episodeUuid: episodeUuid,
        fingerprint: fingerprint,
        segments: segments
    )
    guard !mentions.isEmpty, !Task.isCancelled else { return nil }
    return EpisodeMentionsCardPayload(mentions: mentions, usedModel: usedModel)
}

extension EpisodeDetailViewController: WKNavigationDelegate, @preconcurrency SFSafariViewControllerDelegate { // NOSONAR - WebView navigation is restricted in decidePolicyFor.
    func setupWebView() {
        showNotesWebView = WKWebView()

        showNotesHolderView.insertSubview(showNotesWebView, belowSubview: loadingIndicator)
        showNotesWebView.translatesAutoresizingMaskIntoConstraints = false

        let showNotesWebViewTopConstraint = showNotesWebView.topAnchor.constraint(equalTo: showNotesHolderView.topAnchor, constant: 20)
        self.showNotesWebViewTopConstraint = showNotesWebViewTopConstraint
        NSLayoutConstraint.activate([
            showNotesWebView.leadingAnchor.constraint(equalTo: showNotesHolderView.leadingAnchor),
            showNotesWebView.trailingAnchor.constraint(equalTo: showNotesHolderView.trailingAnchor),
            showNotesWebView.bottomAnchor.constraint(equalTo: showNotesHolderView.bottomAnchor),
            showNotesWebViewTopConstraint
        ])

        showNotesWebView.allowsLinkPreview = true
        showNotesWebView.navigationDelegate = self
        showNotesWebView.isOpaque = false
        showNotesWebView.backgroundColor = UIColor.clear

        showNotesWebView.scrollView.backgroundColor = UIColor.clear
        showNotesWebView.scrollView.isScrollEnabled = false

        showNotesWebView.scrollView.showsVerticalScrollIndicator = false
    }

    private func removeTranscriptExcerptController() {
        guard let transcriptExcerpt else { return }

        for child in children where child.viewIfLoaded?.isDescendant(of: transcriptExcerpt) == true {
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
    }

    func loadShowNotes() {
        if downloadingShowNotes { return }

        loadingIndicator.startAnimating()
        hideErrorMessage(hide: true)

        Task { [weak self] in
            guard let self else { return }

            let parentIdentifier = episode.parentIdentifier()
            let episodeUUID = episode.uuid
            let showNotes = try? await ShowInfoCoordinator.shared.loadShowNotes(podcastUuid: parentIdentifier, episodeUuid: episodeUUID)

            let hideExcerpt: (EpisodeDetailViewController?) -> Void = { vc in
                vc?.removeTranscriptExcerptController()
                vc?.transcriptExcerpt?.isHidden = true
                vc?.showNotesHolderTopAnchor?.constant = 0.0
                vc?.showNotesWebViewTopConstraint?.constant = 20.0
            }
            if let metadata = try? await ShowInfoCoordinator.shared.loadTranscriptsMetadata(podcastUuid: parentIdentifier, episodeUuid: episodeUUID), !metadata.transcripts.isEmpty {
                let viewModel = TranscriptExcerptViewModel(episodeUUID: episodeUUID, podcastUUID: parentIdentifier, isGeneratedTranscript: metadata.hasGeneratedTranscripts) {
                    DispatchQueue.main.async { [weak self] in
                        let playbackManager = TranscriptEpisodeInfoProvider(episodeUUID: episodeUUID, podcastUUID: parentIdentifier)
                        let controller = TranscriptContainerViewController(playbackManager: playbackManager)
                        controller.playButtonTapped = { [weak self] playing in
                            self?.playPauseEpisode(isPlaying: playing)
                        }
                        self?.present(controller, animated: true)
                    }
                }
                await MainActor.run { [weak self] in
                    self?.removeTranscriptExcerptController()
                    let vc = ThemedHostingController(rootView: TranscriptExcerptView(viewModel: viewModel))
                    vc.sizingOptions = [.intrinsicContentSize, .preferredContentSize]
                    let view = vc.view!
                    view.translatesAutoresizingMaskIntoConstraints = false
                    self?.addChild(vc)
                    self?.transcriptExcerpt?.addSubview(view)
                    vc.didMove(toParent: self)
                    view.anchorToAllSidesOf(view: self?.transcriptExcerpt)
                    self?.transcriptExcerpt?.isHidden = false
                    self?.showNotesWebViewTopConstraint?.constant = 0.0
                }
            } else {
                await MainActor.run { [weak self] in
                    hideExcerpt(self)
                }
            }

            downloadingShowNotes = false
            showNotesDidLoad(showNotes: showNotes ?? CacheServerHandler.noShowNotesMessage)

            // The show-info payload is already cached from the loads above, so the
            // credits card costs no extra request; it never attaches when the
            // episode has no credits (the card "self-hides when empty").
            if FeatureFlag.episodeCredits.enabled,
               let persons = (try? await ShowInfoCoordinator.shared.loadShowInfo(podcastUuid: parentIdentifier, episodeUuid: episodeUUID))?.persons,
               !persons.isEmpty {
                await MainActor.run { [weak self] in
                    self?.attachCreditsCardIfNeeded(persons: persons)
                }
            }

            // After the show notes render so the extra -meta.json request never
            // delays them; the card slots in whenever the summary arrives.
            if FeatureFlag.episodeSummaries.enabled,
               let summary = try? await ShowInfoCoordinator.shared.loadEpisodeSummary(podcastUuid: parentIdentifier, episodeUuid: episodeUUID),
               !summary.trim().isEmpty {
                await MainActor.run { [weak self] in
                    self?.attachSummaryCardIfNeeded(summary: summary)
                }
            }

            // Entity mentions come from the on-device transcript index (no
            // network); like the credits card, it self-hides when empty.
            if FeatureFlag.episodeMentions.enabled {
                await loadMentionsCard(episodeUuid: episodeUUID)
            }

            // Episode reactions (Slice 3, docs/Social.md): account-level,
            // counts-only, listen-gated to >=25% of the episode played.
            if FeatureFlag.socialProfiles.enabled, SyncManager.isUserLoggedIn() {
                await MainActor.run { [weak self] in
                    self?.attachReactionsRowIfNeeded()
                    self?.attachCommentsRowIfNeeded()
                }
            }
        }
    }

    /// Hosts the reactions row after the other social/AI cards, using the same
    /// stack-insertion pattern. Idempotent.
    private func attachReactionsRowIfNeeded() {
        guard episodeReactionsContainer == nil,
              let excerptView = transcriptExcerpt,
              let stack = excerptView.superview as? UIStackView else {
            return
        }

        let duration = episode.duration
        let canReact = duration > 0 && episode.playedUpTo >= duration * 0.25
        let viewModel = EpisodeReactionsViewModel(episodeUuid: episode.uuid, canReact: canReact)

        let container = UIView()
        container.backgroundColor = .clear
        container.translatesAutoresizingMaskIntoConstraints = false

        let hostingController = ThemedHostingController(rootView: EpisodeReactionsRowView(viewModel: viewModel))
        hostingController.sizingOptions = [.intrinsicContentSize, .preferredContentSize]
        let hostedView = hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        container.addSubview(hostedView)

        let anchorView = episodeMentionsContainer ?? episodeCreditsContainer ?? episodeSummaryContainer ?? excerptView
        if let index = stack.arrangedSubviews.firstIndex(of: anchorView) {
            stack.insertArrangedSubview(container, at: index + 1)
        } else {
            stack.addArrangedSubview(container)
        }

        hostingController.didMove(toParent: self)
        hostedView.anchorToAllSidesOf(view: container)

        episodeReactionsContainer = container
    }

    /// Hosts the comments entry row under the reactions row (Slice 6,
    /// ADR-0010): a count row that opens the episode's comment tree.
    private func attachCommentsRowIfNeeded() {
        guard episodeCommentsContainer == nil,
              let excerptView = transcriptExcerpt,
              let stack = excerptView.superview as? UIStackView else {
            return
        }

        let duration = episode.duration
        let canSeed = duration > 0 && episode.playedUpTo >= duration * 0.25
        let viewModel = EpisodeCommentsRowViewModel(episodeUuid: episode.uuid,
                                                    podcastUuid: episode.parentIdentifier(),
                                                    episodeTitle: episode.displayableTitle(),
                                                    podcastTitle: podcast.title ?? "",
                                                    canSeed: canSeed,
                                                    canSeedProvider: { [weak self] in
                                                        guard let episode = self?.episode else { return false }
                                                        return episode.duration > 0 && episode.playedUpTo >= episode.duration * 0.25
                                                    })
        viewModel.onOpen = { [weak self] commentsViewModel in
            guard let self else { return }
            let hosting = ThemedHostingController(rootView: EpisodeCommentsView(viewModel: commentsViewModel))
            let navigation = UINavigationController(rootViewController: hosting)
            self.present(navigation, animated: true)
        }

        let container = UIView()
        container.backgroundColor = .clear
        container.translatesAutoresizingMaskIntoConstraints = false

        let hostingController = ThemedHostingController(rootView: EpisodeCommentsRowView(viewModel: viewModel))
        hostingController.sizingOptions = [.intrinsicContentSize, .preferredContentSize]
        let hostedView = hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        container.addSubview(hostedView)

        let anchorView = episodeReactionsContainer ?? episodeMentionsContainer ?? episodeCreditsContainer ?? episodeSummaryContainer ?? excerptView
        if let index = stack.arrangedSubviews.firstIndex(of: anchorView) {
            stack.insertArrangedSubview(container, at: index + 1)
        } else {
            stack.addArrangedSubview(container)
        }

        hostingController.didMove(toParent: self)
        hostedView.anchorToAllSidesOf(view: container)

        episodeCommentsContainer = container
    }

    /// Reads the episode's indexed transcript (generated corpus preferred — its
    /// timeline is native to the local audio), extracts entity mentions, and
    /// attaches the card. Best-effort: no indexed transcript or no validated
    /// entities means no card.
    private func loadMentionsCard(episodeUuid: String) async {
        guard let payload = await episodeMentionsCardPayload(episodeUuid: episodeUuid) else { return }
        attachMentionsCardIfNeeded(mentions: payload.mentions, usedModel: payload.usedModel)
    }

    /// Hosts the mentions card after the credits card (or whatever card is last
    /// in the excerpt stack); same idempotent container pattern as
    /// `attachCreditsCardIfNeeded`.
    private func attachMentionsCardIfNeeded(mentions: [EntityMention], usedModel: Bool) {
        guard episodeMentionsContainer == nil,
              let excerptView = transcriptExcerpt,
              let stack = excerptView.superview as? UIStackView else {
            return
        }

        let viewModel = EpisodeMentionsViewModel(
            mentions: mentions,
            episodeUuid: episode.uuid,
            podcastUuid: episode.parentIdentifier(),
            usedModel: usedModel
        )

        let container = UIView()
        container.backgroundColor = .clear
        container.translatesAutoresizingMaskIntoConstraints = false

        let hostingController = ThemedHostingController(rootView: EpisodeMentionsCardView(viewModel: viewModel))
        hostingController.sizingOptions = [.intrinsicContentSize, .preferredContentSize]
        let hostedView = hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        container.addSubview(hostedView)

        let anchorView = episodeCreditsContainer ?? episodeSummaryContainer ?? excerptView
        if let index = stack.arrangedSubviews.firstIndex(of: anchorView) {
            stack.insertArrangedSubview(container, at: index + 1)
        } else {
            stack.addArrangedSubview(container)
        }

        hostingController.didMove(toParent: self)
        hostedView.anchorToAllSidesOf(view: container)

        episodeMentionsContainer = container
    }

    /// Hosts the AI summary card between the transcript excerpt and the show
    /// notes: a code-created container joins the excerpt's vertical stack right
    /// after the excerpt, and a `ThemedHostingController` child fills it
    /// (plans/AI UX Improvements.md Phase 2). Idempotent — `loadShowNotes()`
    /// can run again via the retry button.
    private func attachSummaryCardIfNeeded(summary: String) {
        guard episodeSummaryContainer == nil,
              let excerptView = transcriptExcerpt,
              let stack = excerptView.superview as? UIStackView else {
            return
        }

        let viewModel = EpisodeSummaryViewModel(
            summary: summary,
            episodeUuid: episode.uuid,
            podcastUuid: episode.parentIdentifier(),
            duration: episode.duration
        )

        let container = UIView()
        container.backgroundColor = .clear
        container.translatesAutoresizingMaskIntoConstraints = false

        let hostingController = ThemedHostingController(rootView: EpisodeSummaryCardView(viewModel: viewModel))
        hostingController.sizingOptions = [.intrinsicContentSize, .preferredContentSize]
        let hostedView = hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        container.addSubview(hostedView)

        if let index = stack.arrangedSubviews.firstIndex(of: excerptView) {
            stack.insertArrangedSubview(container, at: index + 1)
        } else {
            stack.addArrangedSubview(container)
        }

        hostingController.didMove(toParent: self)
        hostedView.anchorToAllSidesOf(view: container)

        episodeSummaryContainer = container
    }

    /// Hosts the people-credits card after the summary card (or the transcript
    /// excerpt when no summary attached yet) and before the show notes, using
    /// the same container pattern as `attachSummaryCardIfNeeded`
    /// (plans/AI UX Improvements.md Phase 6). Order stays deterministic no
    /// matter which card's data arrives first: the summary always inserts right
    /// after the excerpt, credits insert after whichever of the two is present.
    /// Idempotent — `loadShowNotes()` can run again via the retry button.
    private func attachCreditsCardIfNeeded(persons: [Episode.Metadata.Person]) {
        guard episodeCreditsContainer == nil,
              let excerptView = transcriptExcerpt,
              let stack = excerptView.superview as? UIStackView else {
            return
        }

        let viewModel = EpisodeCreditsViewModel(
            persons: persons,
            episodeUuid: episode.uuid,
            podcastUuid: episode.parentIdentifier()
        ) { [weak self] term in
            self?.startPersonSearch(term: term)
        }

        let container = UIView()
        container.backgroundColor = .clear
        container.translatesAutoresizingMaskIntoConstraints = false

        let hostingController = ThemedHostingController(rootView: EpisodeCreditsView(viewModel: viewModel))
        hostingController.sizingOptions = [.intrinsicContentSize, .preferredContentSize]
        let hostedView = hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        container.addSubview(hostedView)

        let anchorView = episodeSummaryContainer ?? excerptView
        if let index = stack.arrangedSubviews.firstIndex(of: anchorView) {
            stack.insertArrangedSubview(container, at: index + 1)
        } else {
            stack.addArrangedSubview(container)
        }

        hostingController.didMove(toParent: self)
        hostedView.anchorToAllSidesOf(view: container)

        episodeCreditsContainer = container
    }

    /// Launches a catalog search for a credited person: dismisses this episode
    /// card, lands on the Podcasts tab, and hands the term to its search UI
    /// (`ExternalSearchRequested` → `SearchResultsViewController.startExternalSearch`).
    private func startPersonSearch(term: String) {
        dismiss(animated: true) {
            NavigationManager.sharedManager.navigateTo(NavigationManager.podcastListPageKey, animated: false)
            // One runloop turn so the tab switch's view hierarchy settles before
            // the search bar takes focus and adopts the term.
            DispatchQueue.main.async {
                NotificationCenter.postOnMainThread(ExternalSearchRequested(term: term))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        showNotesWebView.evaluateJavaScript("document.readyState", completionHandler: { [weak self] complete, _ in
            guard let _ = complete else { return }

            self?.showNotesWebView.evaluateJavaScript("document.body.offsetHeight", completionHandler: { [weak self] height, _ in
                guard let cgHeight = height as? CGFloat else { return }

                self?.showNotesHolderViewHeight.constant = CGFloat(cgHeight) + Constants.Values.extraShowNotesVerticalSpacing
                self?.view.layoutIfNeeded()
            })
        })
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated {
            guard let url = navigationAction.request.url, URLHelper.isAllowedExternalContentLink(url) else {
                decisionHandler(.cancel)
                return
            }

            if let safariViewController = URLHelper.open(
                url,
                context: .externalContent,
                options: .init(
                    presenter: self,
                    prefersExternalBrowser: Settings.openLinks,
                    delegate: self
                )
            ) {
                self.safariViewController = safariViewController
            }
            Analytics.track(.episodeDetailShowNotesLinkTapped, properties: ["episode_uuid": episode.uuid, "source": viewSource])

            decisionHandler(.cancel)
            return
        }

        decisionHandler(URLHelper.isAllowedEmbeddedContentNavigationURL(navigationAction.request.url) ? .allow : .cancel)
    }

    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        safariViewController?.delegate = nil
        safariViewController = nil
    }

    private func showNotesDidLoad(showNotes: String) {
        rawShowNotes = showNotes
        DispatchQueue.main.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.loadingIndicator.stopAnimating()
            strongSelf.renderShowNotes()
        }
    }

    func renderShowNotes() {
        guard let showNotes = rawShowNotes else { return }
        if showNotes == CacheServerHandler.noShowNotesMessage {
            failedToLoadLabel.text = showNotes
            hideErrorMessage(hide: false)
        } else {
            let currentTheme = themeOverride ?? Theme.sharedTheme.activeTheme
            lastThemeRenderedNotesIn = currentTheme
            let formattedNotes = ShowNotesFormatter.format(showNotes: showNotes, tintColor: linkTintColor(), convertTimesToLinks: false, bgColor: ThemeColor.primaryUi01(for: currentTheme), textColor: ThemeColor.primaryText01(for: currentTheme))
            showNotesWebView.loadHTMLString(formattedNotes, baseURL: URL(fileURLWithPath: Bundle.main.bundlePath))
        }
    }

    private func linkTintColor() -> UIColor {
        let currentTheme = themeOverride ?? Theme.sharedTheme.activeTheme

        return ThemeColor.primaryInteractive01(for: currentTheme)
    }
}
