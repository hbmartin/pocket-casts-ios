import PocketCastsServer
import PocketCastsUtils
import UIKit

class ChangePasswordViewController: PCViewController, UITextFieldDelegate {

    /// Set when the password change succeeded server-side but the follow-up
    /// re-authentication (which persists the replacement refresh-token pair) failed.
    /// While set, the main button retries the re-authentication with this new password —
    /// re-running the change with the stale current-password field would always fail.
    private var pendingReauthenticationPassword: String?
    private(set) var isBusy = false

    @IBOutlet var scrollView: UIScrollView!

    @IBOutlet var contentView: ThemeableView! {
        didSet {
            contentView.style = .primaryUi02
        }
    }

    @IBOutlet var currentField: ThemeableTextField! {
        didSet {
            currentField.placeholder = L10n.currentPasswordPrompt
            currentField.delegate = self
            currentField.addTarget(self, action: #selector(ChangePasswordViewController.textFieldDidChange), for: UIControl.Event.editingChanged)
        }
    }

    @IBOutlet var newField: ThemeableTextField! {
        didSet {
            newField.placeholder = L10n.newPasswordPrompt
            newField.delegate = self
            newField.addTarget(self, action: #selector(ChangePasswordViewController.textFieldDidChange), for: UIControl.Event.editingChanged)
        }
    }

    @IBOutlet var confirmField: ThemeableTextField! {
        didSet {
            confirmField.placeholder = L10n.confirmNewPasswordPrompt
            confirmField.delegate = self
            confirmField.addTarget(self, action: #selector(ChangePasswordViewController.textFieldDidChange), for: UIControl.Event.editingChanged)
        }
    }

    @IBOutlet var mainButton: ThemeableRoundedButton! {
        didSet {
            mainButton.isEnabled = false
            mainButton.buttonStyle = .primaryInteractive01Disabled
            mainButton.textStyle = .primaryInteractive02
            mainButton.setTitle(L10n.confirm, for: .normal)
            mainButton.titleLabel?.adjustsFontForContentSizeCategory = true
            mainButton.titleLabel?.font = .font(ofSize: 17, weight: .semibold, scalingWith: .body)
        }
    }

    @IBOutlet var currentBorderView: ThemeableSelectionView! {
        didSet {
            currentBorderView.isSelected = true
            currentBorderView.style = .primaryField02
        }
    }

    @IBOutlet var newBorderView: ThemeableSelectionView! {
        didSet {
            newBorderView.isSelected = false
            newBorderView.style = .primaryField02
        }
    }

    @IBOutlet var confirmBorderView: ThemeableSelectionView! {
        didSet {
            confirmBorderView.isSelected = false
            confirmBorderView.style = .primaryField02
        }
    }

    @IBOutlet var errorView: ThemeableView!
    @IBOutlet var errorLabel: ThemeableLabel! {
        didSet {
            errorLabel.style = .support05
        }
    }

    @IBOutlet var infoLabel: ThemeableLabel! {
        didSet {
            infoLabel.attributedText = NSMutableAttributedString(string: "• " + L10n.changePasswordLengthError)
        }
    }

    @IBOutlet var showCurrentPasswordBtn: UIButton! {
        didSet {
            showCurrentPasswordBtn.tintColor = ThemeColor.primaryIcon03()
        }
    }

    @IBOutlet var showNewPasswordBtn: UIButton! {
        didSet {
            showNewPasswordBtn.tintColor = ThemeColor.primaryIcon03()
        }
    }

    @IBOutlet var showConfirmPasswordBtn: UIButton! {
        didSet {
            showConfirmPasswordBtn.tintColor = ThemeColor.primaryIcon03()
        }
    }

    @IBOutlet var currentKeyImage: UIImageView! {
        didSet {
            currentKeyImage.tintColor = AppTheme.colorForStyle(.primaryField03Active)
        }
    }

    @IBOutlet var newKeyImage: UIImageView! {
        didSet {
            newKeyImage.tintColor = AppTheme.colorForStyle(.primaryField03Active)
        }
    }

    @IBOutlet var confirmKeyImage: UIImageView! {
        didSet {
            confirmKeyImage.tintColor = AppTheme.colorForStyle(.primaryField03Active)
        }
    }

    @IBOutlet var activityIndicatorView: UIActivityIndicatorView! {
        didSet {
            activityIndicatorView.isHidden = true
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.changePassword

        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "cancel"), style: .done, target: self, action: #selector(backTapped))
        navigationController?.navigationBar.setValue(true, forKey: "hidesShadow")

        updateButtonState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
        currentField.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
        currentField.resignFirstResponder()
        newField.resignFirstResponder()
        confirmField.resignFirstResponder()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        AppTheme.defaultStatusBarStyle()
    }

    override func handleThemeChanged() {
        showNewPasswordBtn.tintColor = ThemeColor.primaryIcon03()
        showConfirmPasswordBtn.tintColor = ThemeColor.primaryIcon03()
        showCurrentPasswordBtn.tintColor = ThemeColor.primaryIcon03()
        currentKeyImage.tintColor = ThemeColor.primaryField03Active()
        newKeyImage.tintColor = ThemeColor.primaryField03Active()
        confirmKeyImage.tintColor = ThemeColor.primaryField03Active()
    }

    // MARK: - Actions

    @objc func backTapped() {
        dismiss(animated: true, completion: nil)
    }

    @IBAction func toggleHidePassword(_ sender: UIButton) {
        let tappedButton = sender
        var textFieldToToggle: UITextField!
        if tappedButton == showCurrentPasswordBtn {
            textFieldToToggle = currentField
        } else if tappedButton == showNewPasswordBtn {
            textFieldToToggle = newField
        } else if tappedButton == showConfirmPasswordBtn {
            textFieldToToggle = confirmField
        }

        if let textFieldToToggle {
            textFieldToToggle.isSecureTextEntry.toggle()
            if textFieldToToggle.isSecureTextEntry {
                tappedButton.setImage(UIImage(named: "eye-crossed"), for: .normal)
            } else {
                tappedButton.setImage(UIImage(named: "eye"), for: .normal)
            }
        }
    }

    @IBAction func confirmTapped(_ sender: UIButton) {
        guard !isBusy else { return }

        currentField.resignFirstResponder()
        newField.resignFirstResponder()
        confirmField.resignFirstResponder()
        if let newPassword = pendingReauthenticationPassword {
            retryReauthentication(newPassword: newPassword)
        } else {
            changePassword()
        }
    }

    @objc func changePassword() {
        guard !isBusy else { return }
        guard let currentPassword = currentField.text, let newPassword = newField.text else {
            errorView.isHidden = false
            return
        }

        setBusy(true)
        ApiServerHandler.shared.changePasswordRequest(currentPassword: currentPassword, newPassword: newPassword, completion: { success in
            DispatchQueue.main.async {
                if success {
                    Analytics.track(.userPasswordUpdated)
                    // Busy state stays up: the follow-up re-authentication is part of
                    // the same operation from the user's point of view.
                    self.completeSuccessfulPasswordChange(newPassword: newPassword)
                } else {
                    self.setBusy(false)
                    self.errorView.isHidden = false
                    self.errorLabel.text = L10n.changePasswordError
                }
            }
        })
    }

    private func completeSuccessfulPasswordChange(newPassword: String) {
        guard FeatureFlag.refreshTokenForPasswordAuth.enabled else {
            AuthenticationHelper.persistPasswordForLegacyAuthenticationIfNeeded(newPassword)
            setBusy(false)
            showPasswordUpdatedConfirmation()
            return
        }

        // user/change_password revokes the current refresh-token family. Reauthenticate
        // immediately with the new password; AuthenticationHelper rejects the response
        // unless it carries a non-empty replacement refresh token.
        reauthenticate(newPassword: newPassword)
    }

    private func retryReauthentication(newPassword: String) {
        guard !isBusy else { return }
        setBusy(true)
        reauthenticate(newPassword: newPassword)
    }

    private func reauthenticate(newPassword: String) {
        guard let username = ServerSettings.syncingEmail(), !username.isEmpty else {
            showReauthenticationFailure(newPassword: newPassword)
            return
        }

        Task { @MainActor in
            do {
                _ = try await AuthenticationHelper.validateLogin(username: username, password: newPassword, scope: .mobile)
                pendingReauthenticationPassword = nil
                setBusy(false)
                showPasswordUpdatedConfirmation()
            } catch {
                FileLog.shared.addMessage("Password changed but in-memory reauthentication failed: \(error)")
                showReauthenticationFailure(newPassword: newPassword)
            }
        }
    }

    private func showPasswordUpdatedConfirmation() {
        let updatedVC = AccountUpdatedViewController()
        updatedVC.titleText = L10n.changePasswordConf
        updatedVC.detailText = L10n.funnyConfMsg
        updatedVC.imageName = AppTheme.passwordChangedImageName
        navigationController?.pushViewController(updatedVC, animated: true)
    }

    private func showReauthenticationFailure(newPassword: String) {
        pendingReauthenticationPassword = newPassword
        setBusy(false)
        mainButton.setTitle(L10n.tryAgain, for: .normal)
        errorView.isHidden = false
        errorLabel.text = L10n.clientErrorTokenDeauth
    }

    /// Busy = spinner up, content dimmed, main button blank and untappable — held for
    /// the whole change+re-auth sequence so a second submit can't be triggered.
    /// Kept internal so text-field re-entrancy is regression-testable.
    func setBusy(_ busy: Bool) {
        isBusy = busy
        contentView.isUserInteractionEnabled = !busy
        if busy {
            activityIndicatorView.isHidden = false
            activityIndicatorView.startAnimating()
            mainButton.setTitle("", for: .normal)
            mainButton.isEnabled = false
            mainButton.buttonStyle = .primaryInteractive01Disabled
            contentView.alpha = 0.3
        } else {
            activityIndicatorView.stopAnimating()
            activityIndicatorView.isHidden = true
            mainButton.setTitle(L10n.confirm, for: .normal)
            contentView.alpha = 1
            updateButtonState()
        }
    }

    // MARK: - UITextField Methods

    func textFieldDidBeginEditing(_ textField: UITextField) {
        NotificationCenter.postOnMainThread(TextEditingDidStart())
        if textField == currentField {
            currentBorderView.isSelected = true
            newBorderView.isSelected = false
            confirmBorderView.isSelected = false
            showNewPasswordBtn.isHidden = true
            showCurrentPasswordBtn.isHidden = false
            showConfirmPasswordBtn.isHidden = true
        } else if textField == newField {
            currentBorderView.isSelected = false
            newBorderView.isSelected = true
            confirmBorderView.isSelected = false
            showNewPasswordBtn.isHidden = false
            showCurrentPasswordBtn.isHidden = true
            showConfirmPasswordBtn.isHidden = true
        } else if textField == confirmField {
            currentBorderView.isSelected = false
            newBorderView.isSelected = false
            confirmBorderView.isSelected = true
            showNewPasswordBtn.isHidden = true
            showCurrentPasswordBtn.isHidden = true
            showConfirmPasswordBtn.isHidden = false
        }
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        NotificationCenter.postOnMainThread(TextEditingDidEnd())
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == currentField {
            newField.becomeFirstResponder()
        } else if textField == newField {
            confirmField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
        }

        return true
    }

    // MARK: - Private helpers

    @objc func textFieldDidChange() {
        updateButtonState()
    }

    @objc func confirmFieldDidChange() {
        updateButtonState()
    }

    private func updateButtonState() {
        guard !isBusy else {
            mainButton.isEnabled = false
            mainButton.buttonStyle = .primaryInteractive01Disabled
            return
        }

        if pendingReauthenticationPassword != nil {
            // Retry mode: the action re-runs the re-authentication with the captured
            // new password, so it no longer depends on the fields' contents.
            mainButton.isEnabled = true
            mainButton.buttonStyle = .primaryInteractive01
            return
        }

        mainButton.isEnabled = validFields()
        mainButton.buttonStyle = mainButton.isEnabled ? .primaryInteractive01 : .primaryInteractive01Disabled
    }

    private func validFields() -> Bool {
        guard let currentPassword = currentField.text, let newPassword = newField.text, let confirmPassword = confirmField.text, currentPassword.count > 5, newPassword.count > 5, confirmPassword.count > 5 else {
            errorView.isHidden = true
            return false
        }

        if newField.text != confirmField.text {
            errorLabel.text = L10n.changePasswordErrorMismatch
            errorView.isHidden = false
            return false
        }
        errorView.isHidden = true
        return true
    }

    // MARK: Keyboard management

    private var originalButtonConstant: CGFloat = 49
    @objc func keyboardWillShow(notification: NSNotification) {
        if let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: keyboardSize.height, right: 0)
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
        scrollView.contentInset = UIEdgeInsets.zero
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
