import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils
import UIKit

@MainActor
protocol CreateAccountDelegate: AnyObject {
    func handleAccountCreated()
}

class NewEmailViewController: PCViewController, UITextFieldDelegate {
    weak var delegate: CreateAccountDelegate?

    /// The credentials of the account registration created but sign-in couldn't complete
    /// for. While set, the main button retries that sign-in with these captured values:
    /// the text fields may have been edited since and would no longer identify the
    /// already-created account.
    private var registeredCredentialsAwaitingSignIn: (username: String, password: String)?
    private(set) var isBusy = false

    @IBOutlet var scrollView: UIScrollView!

    @IBOutlet var emailField: ThemeableTextField! {
        didSet {
            emailField.delegate = self
            emailField.addTarget(self, action: #selector(emailFieldDidChange), for: UIControl.Event.editingChanged)
            emailField.placeholder = L10n.signInEmailAddressPrompt
        }
    }

    @IBOutlet var contentView: ThemeableView!
    @IBOutlet var nextButton: ThemeableRoundedButton! {
        didSet {
            nextButton.isEnabled = false
            nextButton.buttonStyle = .primaryInteractive01Disabled
            if FeatureFlag.newOnboardingAccountCreation.enabled {
                nextButton.setTitle(L10n.createAccount, for: .normal)
            } else {
                nextButton.setTitle(L10n.next, for: .normal)
            }
            nextButton.titleLabel?.adjustsFontForContentSizeCategory = true
            nextButton.titleLabel?.numberOfLines = 0

            NSLayoutConstraint.activate([
                nextButton.heightAnchor.constraint(greaterThanOrEqualTo: nextButton.titleLabel!.heightAnchor)
            ])
        }
    }

    @IBOutlet var statusImage: UIImageView! {
        didSet {
            statusImage.tintColor = AppTheme.colorForStyle(.support02)
        }
    }

    @IBOutlet var emailBorderView: ThemeableSelectionView! {
        didSet {
            emailBorderView.layer.borderWidth = 2
            emailBorderView.layer.cornerRadius = 6
            emailBorderView.style = .primaryField02
            emailBorderView.isSelected = true
        }
    }

    @IBOutlet var passwordBorderView: ThemeableSelectionView! {
        didSet {
            passwordBorderView.style = .primaryField02
            passwordBorderView.isSelected = false
            passwordBorderView.layer.borderWidth = 2
            passwordBorderView.layer.cornerRadius = 6
        }
    }

    @IBOutlet var infoLabel: ThemeableLabel! {
        didSet {
            infoLabel.text = "• " + L10n.changePasswordLengthError
        }
    }

    @IBOutlet var passwordField: ThemeableTextField! {
        didSet {
            passwordField.delegate = self
            passwordField.addTarget(self, action: #selector(NewEmailViewController.passwordFieldDidChange), for: UIControl.Event.editingChanged)
            passwordField.placeholder = L10n.signInPasswordPrompt
        }
    }

    @IBOutlet var showPasswordButton: UIButton! {
        didSet {
            showPasswordButton.tintColor = ThemeColor.primaryIcon03()
        }
    }

    @IBOutlet var nextButtonBottomConstraint: NSLayoutConstraint!
    @IBOutlet var activityIndicator: UIActivityIndicatorView! {
        didSet {
            activityIndicator.hidesWhenStopped = true
        }
    }

    @IBOutlet var mailImage: UIImageView! {
        didSet {
            mailImage.tintColor = ThemeColor.primaryField03Active()
        }
    }

    @IBOutlet var keyImage: UIImageView! {
        didSet {
            keyImage.tintColor = ThemeColor.primaryField03Active()
        }
    }

    weak var accountUpdatedDelegate: AccountUpdatedDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.createAccount
        activityIndicator.isHidden = true
        let backImage: UIImage?
        if FeatureFlag.newOnboardingAccountCreation.enabled {
            backImage = UIImage(systemName: "chevron.backward", withConfiguration: UIImage.SymbolConfiguration(textStyle: UIFont.TextStyle(rawValue: "UICTFontTextStyleEmphasizedBody"), scale: .default))
        } else {
            backImage = UIImage(named: "nav-back")
        }
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: backImage, style: .done, target: self, action: #selector(backTapped))
        navigationController?.navigationBar.setValue(true, forKey: "hidesShadow")

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
        originalButtonConstant = nextButtonBottomConstraint.constant

        updateButtonState()

        OnboardingFlow.shared.track(.createAccountShown)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        emailField.becomeFirstResponder()
    }

    // isolated deinit: view controllers deallocate on the main actor; deinit tears down isolated observers
    isolated deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        AppTheme.popupStatusBarStyle()
    }

    override func handleThemeChanged() {
        showPasswordButton.tintColor = ThemeColor.primaryIcon03()
        mailImage.tintColor = ThemeColor.primaryField03Active()
        keyImage.tintColor = ThemeColor.primaryField03Active()
        statusImage.tintColor = ThemeColor.support02()
    }

    // MARK: - Actions

    @objc func backTapped() {
        navigationController?.popViewController(animated: true)
        Analytics.track(.createAccountDismissed)
    }

    @IBAction func nextTapped(_ sender: Any) {
        guard !isBusy else { return }

        if let credentials = registeredCredentialsAwaitingSignIn {
            retryPostRegistrationSignIn(credentials.username, password: credentials.password)
            return
        }

        guard let email = emailField.text, let password = passwordField.text else { return }
        startRegister(email, password: password)
    }

    @IBAction func toggleHidePassword(_ sender: Any) {
        passwordField.isSecureTextEntry.toggle()
        if passwordField.isSecureTextEntry {
            showPasswordButton.setImage(UIImage(named: "eye-crossed"), for: .normal)
        } else {
            showPasswordButton.setImage(UIImage(named: "eye"), for: .normal)
        }
    }

    private func startRegister(_ username: String, password: String) {
        guard !isBusy else { return }
        setBusy(true)
        Analytics.track(.createAccountNextButtonTapped)

        passwordBorderView.layer.borderColor = ThemeColor.primaryUi05().cgColor

        ApiServerHandler.shared.registerAccount(username: username, password: password) { success, userId, error in
            DispatchQueue.main.async {
                if !success {
                    self.setBusy(false)
                    Analytics.track(.userAccountCreationFailed, properties: ["error_code": (error ?? .UNKNOWN).rawValue])

                    FileLog.shared.addMessage("Failed to register new account")
                    if error != .UNKNOWN, let message = error?.localizedDescription, !message.isEmpty {
                        FileLog.shared.addMessage(message)
                        self.showErrorMessage(message)
                    } else {
                        self.showErrorMessage(L10n.accountRegistrationFailed)
                    }
                    self.nextButton.setTitle(L10n.next, for: .normal)
                    return
                }

                FileLog.shared.addMessage("Registered new account for \(username)")

                Task { @MainActor in
                    // Registration returns no tokens, so sign in through the
                    // canonical path: AuthenticationHelper persists the
                    // access/refresh tokens (or the legacy password with
                    // refreshTokenForPasswordAuth off) and posts UserLoginDidChange.
                    do {
                        _ = try await AuthenticationHelper.validateLogin(username: username, password: password, scope: .mobile)
                        NotificationCenter.postOnMainThread(UserSignedIn())
                    } catch {
                        guard !FeatureFlag.refreshTokenForPasswordAuth.enabled else {
                            // The account exists, but without a renewable session it must not
                            // be presented as signed in. Capture the registered credentials so
                            // the button can retry user/login without repeating registration.
                            FileLog.shared.addMessage("Post-registration sign-in did not produce refresh credentials: \(error)")
                            self.showPostRegistrationSignInFailure(username: username, password: password)
                            return
                        }

                        // Flag off preserves the existing rollback behavior byte-for-byte.
                        FileLog.shared.addMessage("Post-registration sign-in failed, falling back to legacy persistence: \(error)")
                        self.saveUsernameAndPassword(username, password: password, userId: userId)
                        RefreshManager.shared.refreshPodcasts(forceEvenIfRefreshedRecently: true)
                    }

                    self.finishAccountCreation()
                }
            }
        }
    }

    private func retryPostRegistrationSignIn(_ username: String, password: String) {
        guard !isBusy else { return }
        setBusy(true)

        Task { @MainActor in
            do {
                _ = try await AuthenticationHelper.validateLogin(username: username, password: password, scope: .mobile)
                NotificationCenter.postOnMainThread(UserSignedIn())
                finishAccountCreation()
            } catch {
                FileLog.shared.addMessage("Post-registration sign-in retry failed: \(error)")
                showPostRegistrationSignInFailure(username: username, password: password)
            }
        }
    }

    private func showPostRegistrationSignInFailure(username: String, password: String) {
        registeredCredentialsAwaitingSignIn = (username, password)
        setBusy(false)
        showErrorMessage(L10n.accountCreatedSignInFailed)
        nextButton.setTitle(L10n.signIn, for: .normal)
    }

    private func finishAccountCreation() {
        registeredCredentialsAwaitingSignIn = nil
        setBusy(false)
        SyncManager.syncReason = .accountCreated

        // Let a delegate decide what to do next
        delegate?.handleAccountCreated()
    }

    // MARK: - Private helpers

    /// Busy covers registration and the required follow-up sign-in as one
    /// non-reentrant operation. Kept internal so the invariant is regression-testable.
    func setBusy(_ busy: Bool) {
        isBusy = busy
        contentView.alpha = busy ? 0.3 : 1
        contentView.isUserInteractionEnabled = !busy
        if busy {
            activityIndicator.isHidden = false
            activityIndicator.startAnimating()
            nextButton.setTitle("", for: .normal)
            nextButton.isEnabled = false
            nextButton.buttonStyle = .primaryInteractive01Disabled
        } else {
            activityIndicator.stopAnimating()
            activityIndicator.isHidden = true
            updateButtonState()
        }
    }

    private func showErrorMessage(_ message: String) {
        infoLabel.text = message
        infoLabel.style = .support05
        if message.lowercased().contains("email") {
            emailBorderView.isSelected = true
            emailBorderView.selectedStyle = .support05
        }
        if message.lowercased().contains("password") {
            passwordBorderView.isSelected = true
            passwordBorderView.selectedStyle = .support05
        }
    }

    private func hideErrorMessage() {
        infoLabel.style = .primaryText01
    }

    private func saveUsernameAndPassword(_ username: String, password: String, userId: String?) {
        ServerSettings.userId = userId
        AuthenticationHelper.persistPasswordForLegacyAuthenticationIfNeeded(password)

        // we've signed in, set all our existing podcasts to be non synced
        DataManager.sharedManager.markAllPodcastsUnsynced()

        ServerSettings.clearLastSyncTime()
        ServerSettings.setSyncingEmail(email: username)

        NotificationCenter.postOnMainThread(UserLoginDidChange())
        NotificationCenter.postOnMainThread(UserSignedIn())
    }

    // MARK: - UITextField Methods

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard !isBusy else { return false }

        if textField == emailField {
            passwordField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
            if let credentials = registeredCredentialsAwaitingSignIn {
                retryPostRegistrationSignIn(credentials.username, password: credentials.password)
            } else {
                startRegister(emailField.text ?? "", password: passwordField.text ?? "")
            }
        }
        return true
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        NotificationCenter.postOnMainThread(TextEditingDidStart())
        if textField == emailField {
            emailBorderView.selectedStyle =
                .primaryField03Active
            emailBorderView.isSelected = true
            passwordBorderView.isSelected = false
        } else {
            passwordBorderView.selectedStyle = .primaryField03Active
            emailBorderView.isSelected = false
            passwordBorderView.isSelected = true
        }
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        NotificationCenter.postOnMainThread(TextEditingDidEnd())
    }

    @objc func emailFieldDidChange() {
        updateButtonState()
    }

    @objc func passwordFieldDidChange() {
        updateButtonState()
        hideErrorMessage()
    }

    private func updateButtonState() {
        guard !isBusy else {
            nextButton.isEnabled = false
            nextButton.buttonStyle = .primaryInteractive01Disabled
            return
        }

        if registeredCredentialsAwaitingSignIn != nil {
            // Sign-in retry mode uses the captured credentials, so the button stays
            // enabled no matter what the fields now contain.
            nextButton.isEnabled = true
            nextButton.buttonStyle = .primaryInteractive01
            statusImage.isHidden = !validEmail()
            return
        }

        nextButton.isEnabled = validEmail() && validPassword()

        nextButton.buttonStyle = nextButton.isEnabled ? .primaryInteractive01 : .primaryInteractive01Disabled
        statusImage.isHidden = !validEmail()
    }

    private func validEmail() -> Bool {
        if let email = emailField.text, email.contains("@") {
            let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
            let emailTest = NSPredicate(format: "SELF MATCHES %@", emailRegEx)
            return emailTest.evaluate(with: email)
        }

        return false
    }

    private func validPassword() -> Bool {
        if let password = passwordField.text {
            return password.count >= 3
        }
        return false
    }

    private var originalButtonConstant: CGFloat = 16
    @objc func keyboardWillShow(notification: NSNotification) {
        if let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            nextButtonBottomConstraint.constant = view.safeAreaInsets.bottom == 0 ? originalButtonConstant + keyboardSize.height : keyboardSize.height

            var animationDuration = 0.3
            if let keyboardDuration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) {
                animationDuration = keyboardDuration
            }

            UIView.animate(withDuration: animationDuration, animations: {
                self.view.layoutIfNeeded()
            }, completion: nil)
        }
    }

    @objc func keyboardWillHide(notification: NSNotification) {
        nextButtonBottomConstraint.constant = originalButtonConstant
        var animationDuration = 0.3
        if let keyboardDuration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) {
            animationDuration = keyboardDuration
        }
        UIView.animate(withDuration: animationDuration, animations: {
            self.view.layoutIfNeeded()
        }, completion: nil)
    }

    // MARK: - Orientation

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }
}
