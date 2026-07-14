import SwiftUI
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils

// MARK: - SwiftUI View

struct SyncSigninView: View {
    @StateObject private var model: SyncSigninViewModel

    let coordinator: LoginCoordinator
    let loginAgain: Bool
    var onCompleted: (() -> Void)?

    init(coordinator: LoginCoordinator, loginAgain: Bool, onCompleted: (() -> Void)? = nil) {
        self.coordinator = coordinator
        self.loginAgain = loginAgain
        self.onCompleted = onCompleted
        self._model = StateObject(wrappedValue: SyncSigninViewModel(coordinator: coordinator))
    }

    @EnvironmentObject var theme: Theme
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                email()
                password()

                if let error = model.errorMessage, !error.isEmpty {
                    Text(error)
                        .font(.callout)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }

                forgotPassword()

                signInButton()

                // Add bottom padding to ensure content doesn't get cut off
                Color.clear.frame(height: 50)
            }
            .padding()
        }
        .background(theme.primaryUi01)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(L10n.accountLogin)
        .toolbarBackground(theme.primaryUi01, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            model.onCompleted = {
                onCompleted?() ?? dismiss()
            }
            model.onAppear(loginAgain: loginAgain)
            focusedField = .email
        }
        .onDisappear { model.onDisappear() }
    }

    private var promptColor: Color {
        theme.primaryField03
    }

    @ViewBuilder private func email() -> some View {
        HStack(spacing: 10) {
            Image("mail")
                .foregroundStyle(theme.primaryField03Active)
                .frame(width: 20)
            TextField(L10n.signInEmailAddressPrompt, text: $model.email, prompt: Text(L10n.signInEmailAddressPrompt).foregroundColor(promptColor))
                .font(.subheadline)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.next)
                .focused($focusedField, equals: .email)
                .onSubmit { focusedField = .password }
                .onChange(of: model.email) { _, _ in model.textFieldChanged() }
        }
        .padding(9)
        .themedTextField(hasErrored: model.errorMessage != nil)
    }

    @ViewBuilder private func password() -> some View {
        HStack(spacing: 10) {
            Image("key")
                .foregroundStyle(theme.primaryField03Active)
                .frame(width: 20)
            HStack(spacing: 8) {
                Group {
                    if model.showPassword {
                        TextField(L10n.signInPasswordPrompt, text: $model.password, prompt: Text(L10n.signInPasswordPrompt).foregroundColor(promptColor))
                    } else {
                        SecureField(L10n.signInPasswordPrompt, text: $model.password, prompt: Text(L10n.signInPasswordPrompt).foregroundColor(promptColor))
                    }
                }
                .font(.subheadline)
                .textContentType(.password)
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit { model.performSignIn() }

                Button(action: { model.toggleShowPassword() }) {
                    Image(model.showPassword ? "eye" : "eye-crossed")
                        .renderingMode(.template)
                }
                .accessibilityLabel(model.showPassword ? L10n.signInHidePasswordLabel : L10n.signInShowPasswordLabel)
                .tint(theme.primaryIcon03)
            }
            .onChange(of: model.password) { _, _ in model.textFieldChanged() }
        }
        .padding(9)
        .themedTextField(hasErrored: model.errorMessage != nil)
    }

    @ViewBuilder private func forgotPassword() -> some View {
        Button(L10n.signInForgotPassword) {
            model.forgotPasswordTapped()
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.primaryInteractive01)
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func signInButton() -> some View {
        Button {
            focusedField = nil
            model.performSignIn()
        } label: {
            ZStack {
                Text(L10n.signInContinueWithEmail)
                    .opacity(model.isSigningIn ? 0 : 1)
                if model.isSigningIn {
                    ProgressView().controlSize(.regular)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16)
        .buttonStyle(RoundedButtonStyle(theme: theme, isEnabled: model.isValid && !model.isSigningIn, maxContentSizeCategory: .accessibilityMedium))
    }

    @ViewBuilder func divider() -> some View {
        HStack(spacing: 15) {
            Rectangle()
                .foregroundStyle(theme.primaryUi05)
                .frame(height: 1)
            Text(L10n.signInDividerLabel)
                .font(.caption)
            Rectangle()
                .foregroundStyle(theme.primaryUi05)
                .frame(height: 1)
        }
    }
}

// MARK: - ViewModel

@MainActor
final class SyncSigninViewModel: ObservableObject {
    // Dependencies
    private let coordinator: LoginCoordinator

    // Inputs
    @Published var email: String = ""
    @Published var password = String()
    @Published var showPassword = false

    // UI state
    @Published var errorMessage: String?
    @Published var isSigningIn = false

    private var progressAlert: SyncLoadingAlert?

    var onCompleted: (() -> Void)?

    init(coordinator: LoginCoordinator) {
        self.coordinator = coordinator
    }

    // Progress tracking
    private var totalPodcastsToImport: Int = -1
    private var messageTokens: [NotificationCenter.ObservationToken] = []

    var isValid: Bool {
        email.contains("@") && email.count >= 3 && password.count >= 3
    }

    func onAppear(loginAgain: Bool) {
        Analytics.track(.signInShown)

        if messageTokens.isEmpty {
            messageTokens = [
                NotificationCenter.default.addObserver(for: SyncProgressPodcastCountKnown.self) { [weak self] message in
                    self?.totalPodcastsToImport = message.count
                },

                // Note: SyncLoadingAlert handles progress notifications automatically via its own subscriptions

                // Complete on any of these
                NotificationCenter.default.addObserver(for: SyncCompleted.self) { [weak self] _ in
                    self?.syncCompleted()
                },
                NotificationCenter.default.addObserver(for: SyncFailed.self) { [weak self] _ in
                    self?.syncCompleted()
                },
                NotificationCenter.default.addObserver(for: PodcastRefreshFailed.self) { [weak self] _ in
                    self?.syncCompleted()
                }
            ]
        }

        // Auto-login if requested
        if loginAgain,
           let syncingEmail = ServerSettings.syncingEmail(),
           let password = ServerSettings.syncingPassword() {
            startSignIn(username: syncingEmail, password: password)
        }
    }

    func onDisappear() {
        let tokens = messageTokens
        messageTokens = []
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // Property reads must precede any call that copies self; a plain deinit
    // may read stored state directly (Swift 6.2 isolated-deinit rule).
    deinit {
        let tokens = messageTokens
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func toggleShowPassword() { showPassword.toggle() }

    func textFieldChanged() {
        errorMessage = nil
        // Button state reacts via @Published + computed isValid
    }

    func forgotPasswordTapped() {
        let vc = ForgotPasswordViewController()
        vc.delegate = self
        SceneHelper.rootViewController()?.navigationController?.pushViewController(vc, animated: true)
    }

    func performSignIn() {
        guard isValid else { return }
        startSignIn(username: email, password: password)
    }

    private func startSignIn(username: String, password: String) {
        isSigningIn = true
        errorMessage = nil

        Task { @MainActor [weak self] in
            guard let self else { return }

            // Show the progress HUD *before* validateLogin: the refresh it kicks
            // off can post SyncCompleted/SyncFailed before the call returns, and
            // syncCompleted() must find the alert to dismiss it (a late-created
            // alert would never be torn down).
            self.progressAlert = SyncLoadingAlert()
            if let navigationController = self.coordinator.navigationController {
                self.progressAlert?.showAlert(navigationController, hasProgress: false, completion: nil)
            }

            do {
                // AuthenticationHelper is the canonical sign-in path: it clears
                // stale keychain tokens, persists the access/refresh tokens (or
                // the legacy password with refreshTokenForPasswordAuth off),
                // marks podcasts unsynced, posts UserLoginDidChange and kicks a
                // refresh. The old callback API discarded the returned tokens.
                _ = try await AuthenticationHelper.validateLogin(username: username, password: password, scope: .mobile)

                Analytics.track(.userSignedIn, properties: ["source": "password"])

                NotificationCenter.postOnMainThread(UserSignedIn())
                self.isSigningIn = false
            } catch {
                let apiError = error as? APIError
                Analytics.track(.userSignInFailed, properties: [
                    "source": "password",
                    "error_code": (apiError ?? .UNKNOWN).rawValue
                ])

                if let apiError, apiError != .UNKNOWN, !apiError.localizedDescription.isEmpty {
                    self.errorMessage = apiError.localizedDescription
                } else {
                    self.errorMessage = L10n.syncAccountError
                }

                self.isSigningIn = false
                self.progressAlert?.hideAlert(false)
                self.progressAlert = nil
            }
        }
    }

    private func syncCompleted() {
        // Without an alert to dismiss, still complete — dropping onCompleted
        // would strand the user on the sign-in screen after a successful sync.
        guard let progressAlert else {
            onCompleted?()
            return
        }
        progressAlert.hideAlert(true) { [weak self] in
            self?.progressAlert = nil
            self?.onCompleted?()
        }
    }
}

// MARK: - ForgotPassword delegate bridge

extension SyncSigninViewModel: ForgotPasswordDelegate {
    func handlePasswordResetSuccess() {
        // In the UIKit VC, it pops then shows an alert slightly later.
        // Here we mimic just the confirmation alert behavior.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if let rootVC = SceneHelper.rootViewController() {
                SJUIUtils.showAlert(
                    title: L10n.profileSendingResetEmailConfTitle,
                    message: L10n.profileSendingResetEmailConfMsg,
                    from: rootVC
                )
            }
        }
    }
}

#Preview {
    SyncSigninView(coordinator: LoginCoordinator(), loginAgain: false)
        .environmentObject(Theme(previewTheme: .light))
}
