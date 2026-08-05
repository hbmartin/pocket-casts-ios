import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils
import UIKit

class ImportExportViewController: PCViewController, @preconcurrency UIDocumentInteractionControllerDelegate {
    private var opmlShareController: UIDocumentInteractionController?

    @IBOutlet var importPocdcastsTitle: UILabel! {
        didSet {
            importPocdcastsTitle.text = L10n.importPodcastsTitle.localizedUppercase
        }
    }

    @IBOutlet var importPodcastsDescription: ThemeableLabel! {
        didSet {
            importPodcastsDescription.text = FeatureFlag.useFollowNaming.enabled ? L10n.importPodcastsDescriptionNew : L10n.importPodcastsDescription
        }
    }

    @IBOutlet var exportPodcastsTitle: UILabel! {
        didSet {
            exportPodcastsTitle.text = L10n.exportPodcastsTitle.localizedUppercase
        }
    }

    @IBOutlet var exportPodcastsDescription: ThemeableLabel! {
        didSet {
            exportPodcastsDescription.text = L10n.exportPodcastsDescription
        }
    }

    @IBOutlet var importView: ThemeableView! {
        didSet {
            importView.style = .primaryUi01Active
        }
    }

    @IBOutlet var exportView: ThemeableView! {
        didSet {
            exportView.style = .primaryUi01Active
        }
    }

    @IBOutlet var importImage: UIImageView! {
        didSet {
            importImage.image = Theme.isDarkTheme() ? UIImage(named: "settings_importillustration_dark") : UIImage(named: "settings_importillustration")
        }
    }

    @IBOutlet var exportBtn: UIButton! {
        didSet {
            exportBtn.setTitle(L10n.exportPodcastsOption, for: .normal)
            exportBtn.titleLabel?.font = .font(ofSize: 13, scalingWith: .subheadline)
            exportBtn.titleLabel?.adjustsFontForContentSizeCategory = true
            exportBtn.titleLabel?.numberOfLines = 0
            exportBtn.titleLabel?.lineBreakMode = .byWordWrapping
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = L10n.exportPodcastsOption
        Analytics.track(.settingsImportShown)
    }

    @IBOutlet var mainScrollView: UIScrollView!

    @IBAction func exportPodcasts(_ sender: AnyObject) {
        Analytics.track(.settingsImportExportTapped)
        startExport()
    }

    /// Builds the OPML entirely from local rows — no server round trip. Podcasts whose
    /// rows never stored a feed URL (legacy server-sourced rows) are skipped.
    private func startExport() {
        Analytics.track(.settingsImportExportStarted)

        let podcasts = DataManager.sharedManager.allPodcasts(includeUnsubscribed: false)
        let feeds = podcasts
            .compactMap { podcast -> OpmlFeed? in
                guard let url = podcast.podcastUrl, !url.isEmpty else { return nil }
                guard let sanitizedURL = Self.strippingCredentials(from: url) else { return nil }
                return OpmlFeed(title: podcast.title ?? "", url: sanitizedURL)
            }

        guard !feeds.isEmpty, feeds.count == podcasts.count else {
            presentError()
            Analytics.track(.settingsImportExportFailed)
            return
        }

        shareOpmlDocument(OpmlDocument.xmlString(feeds: feeds))
        Analytics.track(.settingsImportExportFinished)
    }

    /// Exported OPML must never leak userinfo embedded in a stored feed URL.
    nonisolated static func strippingCredentials(from url: String) -> String? {
        guard var components = URLComponents(string: url) else { return nil }
        components.user = nil
        components.password = nil
        return components.string
    }

    private func shareOpmlDocument(_ text: String) {
        let homeDirectory = NSTemporaryDirectory() as NSString
        let filePath = homeDirectory.appendingPathComponent("podcasts.opml")
        do {
            try text.write(toFile: filePath, atomically: true, encoding: String.Encoding.utf8)

            let fileUrl = URL(fileURLWithPath: filePath)
            opmlShareController = UIDocumentInteractionController(url: fileUrl)
            opmlShareController?.delegate = self

            let presentRect = view.convert(exportBtn.frame, from: exportBtn.superview)
            opmlShareController?.presentOptionsMenu(from: presentRect, in: view, animated: true)
        } catch {
            presentError()
        }
    }

    func documentInteractionControllerDidDismissOptionsMenu(_ controller: UIDocumentInteractionController) {
        opmlShareController = nil
    }

    private func presentError() {
        SJUIUtils.showAlert(title: L10n.settingsExportError, message: L10n.settingsExportErrorMsg, from: self)
    }
}
