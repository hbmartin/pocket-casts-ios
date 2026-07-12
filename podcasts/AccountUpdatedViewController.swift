import PocketCastsServer
import UIKit

protocol AccountUpdatedDelegate: AnyObject {
    func accountUpdatedAcknowledged()
}

class AccountUpdatedViewController: UIViewController {
    @IBOutlet var titleLabel: ThemeableLabel!
    @IBOutlet var detailLabel: ThemeableLabel! {
        didSet {
            detailLabel.style = .primaryText02
        }
    }

    @IBOutlet var imageView: UIImageView!

    @IBOutlet var doneBtn: ThemeableRoundedButton! {
        didSet {
            doneBtn.setTitle(L10n.done.localizedCapitalized, for: .normal)
        }
    }

    var titleText: String?
    var detailText: String?
    var imageName: (() -> String)?
    weak var delegate: AccountUpdatedDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = ""

        titleLabel.text = titleText
        detailLabel.text = detailText
        if let imageNameFunc = imageName {
            imageView.image = UIImage(named: imageNameFunc())
        }
        let closeButton = UIBarButtonItem(image: UIImage(named: "cancel"), style: .done, target: self, action: #selector(closeTapped(_:)))
        closeButton.accessibilityLabel = L10n.accessibilityCloseDialog
        navigationItem.leftBarButtonItem = closeButton

        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: Constants.Notifications.themeChanged, object: nil)

        Analytics.track(.accountUpdatedShown)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        AppTheme.popupStatusBarStyle()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

    @IBAction func closeTapped(_ sender: Any) {
        if let delegate {
            delegate.accountUpdatedAcknowledged()
            return
        }
        dismiss(animated: true, completion: nil)
        Analytics.track(.accountUpdatedDismissed)
    }

    @objc private func themeDidChange() {
        if let imageNameFunc = imageName {
            imageView.image = UIImage(named: imageNameFunc())
        }
    }
}
