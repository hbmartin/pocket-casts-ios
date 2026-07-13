import PocketCastsServer
import PocketCastsUtils
import UIKit

class AccountViewController: UIViewController, ChangeEmailDelegate {
    enum TableRow { case changeEmail, changePassword, logout, deleteAccount, privacyPolicy, termsOfUse }
    var tableData: [[TableRow]] = [[.changeEmail, .changePassword], [.privacyPolicy, .termsOfUse], [.logout], [.deleteAccount]]

    static let actionCellId = "AccountActionCellId"

    private var isUsernamePasswordLogin: Bool {
        // Prefer the explicit auth-method marker (written at sign-in/migration once
        // refresh-token auth is on); fall back to inferring from the stored password
        // for accounts signed in before the marker existed.
        if let authMethod = ServerSettings.accountAuthMethod {
            return authMethod == .password
        }

        return ServerSettings.syncingPassword() != nil
    }

    @IBOutlet var tableView: ThemeableTable! {
        didSet {
            tableView.applyInsetForMiniPlayer()
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
        view.backgroundColor = .clear

        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.accountTitle

        themeToken = NotificationCenter.default.addObserver(for: ThemeChanged.self) { [weak self] _ in
            self?.updateDisplayedData() // in case the avatar text color needs updating
        }

        tableView.tableHeaderView = updatedHeaderContentView
    }

    private var themeToken: NotificationCenter.ObservationToken?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateDisplayedData()
        title = L10n.accountTitle
    }

    deinit {
        let token = themeToken
        NotificationCenter.default.removeObserver(self)
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        AppTheme.defaultStatusBarStyle()
    }

    private func updateDisplayedData() {
        headerViewModel.update()

        // Only accounts created with username/password can change email/password
        let accountOptions: [TableRow] = isUsernamePasswordLogin ? [.changeEmail, .changePassword] : []
        let newTableRows: [[TableRow]] = [accountOptions, [.privacyPolicy, .termsOfUse], [.logout], [.deleteAccount]].filter { !$0.isEmpty }

        updateTableRows(newRows: newTableRows)
    }

    private func updateTableRows(newRows: [[TableRow]]) {
        guard tableData != newRows else { return }

        tableData = newRows
        tableView.reloadData()
    }

    // MARK: - Actions

    @IBAction func learnMoreTapped(_ sender: Any) {
        // Every feature is free now, so there is no plus marketing page to show.
    }

    // MARK: Change email delegate

    func emailChanged() {
        DispatchQueue.main.async {
            self.headerViewModel.update()
        }
    }
}
