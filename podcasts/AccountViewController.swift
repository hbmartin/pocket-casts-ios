import PocketCastsServer
import PocketCastsUtils
import UIKit

class AccountViewController: UIViewController, ChangeEmailDelegate {
    enum TableRow { case changeAvatar, changeEmail, changePassword, newsletter, logout, deleteAccount, privacyPolicy, termsOfUse, supporterContributions }
    var tableData: [[TableRow]] = [[.changeEmail, .changePassword, .newsletter], [.privacyPolicy, .termsOfUse], [.logout], [.deleteAccount]]

    static let newsletterCellId = "NewsletterCellId"
    static let actionCellId = "AccountActionCellId"

    private var isUsernamePasswordLogin: Bool {
        ServerSettings.syncingPassword() != nil
    }

    @IBOutlet var tableView: ThemeableTable! {
        didSet {
            tableView.applyInsetForMiniPlayer()
            tableView.register(UINib(nibName: "NewsletterCell", bundle: nil), forCellReuseIdentifier: AccountViewController.newsletterCellId)
            tableView.register(UINib(nibName: "AccountActionCell", bundle: nil), forCellReuseIdentifier: AccountViewController.actionCellId)
        }
    }

    lazy var headerViewModel: AccountHeaderViewModel = {
        let viewModel = AccountHeaderViewModel()

        viewModel.viewContentSizeChanged = { [weak self] in
            self?.updatedHeaderContentView.frame = .init(x: 0, y: 0, width: self?.headerViewModel.contentSize?.width ?? 0, height: self?.headerViewModel.contentSize?.height ?? 0)
            self?.tableView.reloadData()
        }

        return viewModel
    }()

    lazy var updatedHeaderContentView: UIView = {
        let headerView = AccountHeaderView(viewModel: headerViewModel)

        let view = headerView.themedUIView
        if FeatureFlag.newOnboardingUpgrade.enabled {
            view.backgroundColor = AppTheme.colorForStyle(.primaryUi03, themeOverride: nil)
            self.tableView.themeStyle =  ThemeStyle.primaryUi03
        } else {
            view.backgroundColor = .clear
        }

        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.accountTitle

        NotificationCenter.default.addObserver(self, selector: #selector(subscriptionStatusChanged), name: ServerNotifications.subscriptionStatusChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: Constants.Notifications.themeChanged, object: nil)

        tableView.tableHeaderView = updatedHeaderContentView
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateDisplayedData()
        title = L10n.accountTitle
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        title = ""
        if FeatureFlag.newAccountUpgradePromptFlow.enabled {
            OnboardingFlow.shared.reset()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        AppTheme.defaultStatusBarStyle()
    }

    @objc private func subscriptionStatusChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.updateDisplayedData()
        }
    }

    private func updateDisplayedData() {
        headerViewModel.update()

        // Only accounts created with username/password can change email/password
        var accountOptions: [TableRow]
        if isUsernamePasswordLogin {
            accountOptions = [.changeEmail, .changePassword, .newsletter]
        } else {
            accountOptions = [.newsletter]
        }
        if headerViewModel.profile.isLoggedIn {
            accountOptions.insert(.changeAvatar, safelyAt: 0)
        }

        var newTableRows: [[TableRow]] = [accountOptions, [.privacyPolicy, .termsOfUse], [.logout], [.deleteAccount]]

        if let subscriptionPodcasts = SubscriptionHelper.subscriptionPodcasts(), !subscriptionPodcasts.isEmpty {
            newTableRows[0].insert(.supporterContributions, at: 0)
        }

        updateTableRows(newRows: newTableRows)
    }

    private func updateTableRows(newRows: [[TableRow]]) {
        guard tableData != newRows else { return }

        tableData = newRows
        tableView.reloadData()
    }

    // MARK: - Actions

    @objc func newsletterOptInChanged(_ sender: UISwitch) {
        Analytics.track(.newsletterOptInChanged, properties: ["enabled": sender.isOn, "source": "profile"])

        ServerSettings.setMarketingOptIn(sender.isOn)
        ServerSettings.syncSettings()
    }

    @IBAction func learnMoreTapped(_ sender: Any) {
        // Every feature is free now, so there is no plus marketing page to show.
    }

    @objc func themeDidChange() {
        updateDisplayedData() // in case the expiry text color neds updating
    }

    // MARK: Change email delegate

    func emailChanged() {
        DispatchQueue.main.async {
            self.headerViewModel.update()
        }
    }
}
