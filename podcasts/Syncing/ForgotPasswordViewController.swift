import PocketCastsServer
import UIKit

@MainActor
protocol ForgotPasswordDelegate: AnyObject {
    func handlePasswordResetSuccess()
}
class ForgotPasswordViewController: PCViewController, UITextFieldDelegate {
    weak var delegate: ForgotPasswordDelegate?

    @IBOutlet var resetPasswordBtn: ThemeableRoundedButton! {
        didSet {
            resetPasswordBtn.setTitle(L10n.profileResetPassword, for: .normal)
            resetPasswordBtn.buttonStyle = .primaryInteractive01
            resetPasswordBtn.titleLabel?.numberOfLines = 0
            resetPasswordBtn.titleLabel?.adjustsFontForContentSizeCategory = true
            resetPasswordBtn.titleLabel?.font = UIFont.font(ofSize: 17, weight: .semibold, scalingWith: .headline)
            NSLayoutConstraint.activate([
                resetPasswordBtn.heightAnchor.constraint(greaterThanOrEqualTo: resetPasswordBtn.titleLabel!.heightAnchor)
            ])
        }
    }

    @IBOutlet var emailField: ThemeableTextField! {
        didSet {
            emailField.placeholder = L10n.signInEmailAddressPrompt
            emailField.delegate = self
            emailField.addTarget(self, action: #selector(ForgotPasswordViewController.emailFieldDidChange), for: UIControl.Event.editingChanged)
        }
    }

    @IBOutlet var emailBorderView: ThemeableSelectionView! {
        didSet {
            emailBorderView.isSelected = true
            emailBorderView.layer.cornerRadius = 6
            emailBorderView.layer.borderWidth = 2
        }
    }

    @IBOutlet var messageView: UIView!
    @IBOutlet var errorMessage: ThemeableLabel! {
        didSet {
            errorMessage.style = .support05
        }
    }

    @IBOutlet var errorImage: UIImageView! {
        didSet {
            errorImage.tintColor = AppTheme.colorForStyle(.support05)
        }
    }

    @IBOutlet var mailImage: UIImageView! {
        didSet {
            mailImage.tintColor = AppTheme.colorForStyle(.primaryField03Active)
        }
    }

    @IBOutlet var mainButtonTopSpace: NSLayoutConstraint!

    private var progressAlert: ShiftyLoadingAlert?

    override func viewDidLoad() {
        super.viewDidLoad()

        title = L10n.profileResetPassword
        resetPasswordBtn.isEnabled = false
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "nav-back"), style: .done, target: self, action: #selector(closeTapped))
        Analytics.track(.forgotPasswordShown)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateButtonState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.navigationBar.tintColor = AppTheme.navBarIconsColor()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        Analytics.track(.forgotPasswordDismissed)
    }

    @objc func emailFieldDidChange() {
        updateButtonState()
        hideErrorMessage()
    }

    override func handleThemeChanged() {
        errorImage.tintColor = AppTheme.colorForStyle(.support05)
        mailImage.tintColor = AppTheme.colorForStyle(.primaryField03Active)
    }

    @IBAction func performResetPassword(_ sender: Any) {
        guard let email = emailField.text else { return }

        presentResetPasswordPrompt(email: email)
    }

    private func presentResetPasswordPrompt(email: String, code: String = "", password: String = "", validationFailed: Bool = false) {
        let prompt = UIAlertController(
            title: L10n.profileResetPassword,
            message: validationFailed
                ? "\(L10n.profileResetPasswordInvalidInput)\n\n\(L10n.profileResetPasswordPromptMessage)"
                : L10n.profileResetPasswordPromptMessage,
            preferredStyle: .alert
        )
        prompt.addTextField { field in
            field.placeholder = L10n.profileResetPasswordCodePlaceholder
            field.text = code
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.textContentType = .oneTimeCode
        }
        prompt.addTextField { field in
            field.placeholder = L10n.profileResetPasswordNewPlaceholder
            field.text = password
            field.isSecureTextEntry = true
            field.textContentType = .newPassword
        }
        prompt.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
        prompt.addAction(UIAlertAction(title: L10n.profileResetPassword, style: .default) { [weak self, weak prompt] _ in
            // The backend contract is byte-based (docs/ServerAPISurface.md:
            // "a 12–72-byte password"), so validation counts UTF-8 bytes and
            // the copy above states the same limits.
            guard let self else { return }
            let enteredCode = prompt?.textFields?[0].text ?? ""
            let enteredPassword = prompt?.textFields?[1].text ?? ""
            let normalizedCode = enteredCode.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedCode.isEmpty,
                  enteredPassword.utf8.count >= 12,
                  enteredPassword.utf8.count <= 72 else {
                // Alert actions dismiss before their handlers execute. Re-present
                // on the next run-loop turn with both values retained so the user
                // can correct the invalid field in place.
                DispatchQueue.main.async { [weak self] in
                    self?.presentResetPasswordPrompt(
                        email: email,
                        code: enteredCode,
                        password: enteredPassword,
                        validationFailed: true
                    )
                }
                return
            }
            self.progressAlert = ShiftyLoadingAlert(title: L10n.profileResetPassword)
            self.progressAlert?.showAlert(self, hasProgress: false) {
                self.startPasswordReset(email: email, code: normalizedCode, password: enteredPassword)
            }
        })
        present(prompt, animated: true)
    }

    private func startPasswordReset(email: String, code: String, password: String) {
        emailField.resignFirstResponder()

        ApiServerHandler.shared.resetPassword(email: email, code: code, newPassword: password) { success, error in
            DispatchQueue.main.async {
                self.progressAlert?.hideAlert(false)
                self.progressAlert = nil

                if !success {
                    if error != .UNKNOWN, let message = error?.localizedDescription, !message.isEmpty {
                        self.showErrorMessage(message)
                    } else {
                        self.showErrorMessage(L10n.profileResetPasswordFailed)
                    }

                    return
                }

                Analytics.track(.userPasswordReset)

                guard let delegate = self.delegate else {
                    self.navigationController?.popViewController(animated: true)
                    SJUIUtils.showAlert(title: L10n.profileResetPassword, message: L10n.profileResetPasswordSuccess, from: self)
                    return
                }

                delegate.handlePasswordResetSuccess()
            }
        }
    }

    private func showErrorMessage(_ message: String) {
        errorMessage.text = message
        mainButtonTopSpace.constant = 0
        messageView.isHidden = false
    }

    private func hideErrorMessage() {
        messageView.isHidden = true
    }

    private func updateButtonState() {
        resetPasswordBtn.isEnabled = validFields()
        resetPasswordBtn.buttonStyle = resetPasswordBtn.isEnabled ? .primaryInteractive01 : .primaryInteractive01Disabled
    }

    private func validFields() -> Bool {
        if let email = emailField.text {
            return email.count >= 3 && email.contains("@")
        }

        return false
    }

    // MARK: - UITextFieldDelegate

    func textFieldDidBeginEditing(_ textField: UITextField) {
        NotificationCenter.postOnMainThread(TextEditingDidStart())
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        NotificationCenter.postOnMainThread(TextEditingDidEnd())
    }

    // MARK: - Orientation

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait // since this controller is presented modally it needs to tell iOS it only goes portrait
    }

    @objc func closeTapped() {
        emailField.resignFirstResponder()
        navigationController?.popViewController(animated: true)
    }
}
