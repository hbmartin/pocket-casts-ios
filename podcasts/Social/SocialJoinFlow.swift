import SwiftUI
import PocketCastsServer
import PocketCastsUtils

/// The one-time opt-in Join flow (docs/Social.md decision 3, ADR-0005):
/// terms explainer → immutable-handle claim with live availability →
/// confirm seeded display name → privacy nudge. Presented from the Profile
/// tab CTA row, the one-time announcement, or the retargeted share button.
/// Gated by FeatureFlag.socialProfiles + a logged-in synced account.
struct SocialJoinView: View {
    @EnvironmentObject var theme: Theme
    @StateObject var viewModel: SocialJoinViewModel

    var body: some View {
        NavigationView {
            content
                .navigationBarTitleDisplayMode(.inline)
                .background(AppTheme.color(for: .primaryUi01, theme: theme).ignoresSafeArea())
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder private var content: some View {
        switch viewModel.step {
        case .terms:
            termsStep
        case .handle:
            handleStep
        case .confirm:
            confirmStep
        case .privacyNudge:
            SocialPrivacySettingsView(viewModel: SocialPrivacySettingsViewModel(profile: viewModel.joinedProfile),
                                      isNudge: true,
                                      onDone: { viewModel.finish() })
        }
    }

    // MARK: - Steps

    private var termsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.socialJoinTitle)
                .font(.title.bold())
            Text(L10n.socialJoinIntro)
            Label(L10n.socialJoinPointPrivate, systemImage: "lock")
            Label(L10n.socialJoinPointHandle, systemImage: "at")
            Label(L10n.socialJoinPointErase, systemImage: "trash")
            Text(L10n.socialJoinTerms)
                .font(.footnote)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            Spacer()
            Button(action: { viewModel.acceptTerms() }) {
                Text(L10n.socialJoinAgree)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(RoundedButtonStyle(theme: theme))
        }
        .padding()
        .navigationTitle(L10n.socialJoinTitle)
        .toolbar { cancelItem }
    }

    private var handleStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.socialHandlePrompt)
                .font(.headline)
            HStack {
                Text("@")
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                TextField(L10n.socialHandlePlaceholder, text: $viewModel.handleInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
            }
            .padding(12)
            .background(AppTheme.color(for: .primaryUi02, theme: theme))
            .cornerRadius(8)

            availabilityLine

            Text(L10n.socialHandlePermanent)
                .font(.footnote)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))

            Spacer()
            Button(action: { viewModel.confirmHandle() }) {
                Text(L10n.next)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(RoundedButtonStyle(theme: theme))
            .disabled(!viewModel.availability.isClaimable)
        }
        .padding()
        .navigationTitle(L10n.socialHandleTitle)
        .toolbar { cancelItem }
    }

    @ViewBuilder private var availabilityLine: some View {
        switch viewModel.availabilityDisplay {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(L10n.socialHandleChecking)
            }
            .font(.footnote)
            .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        case .available(let normalized):
            Label(L10n.socialHandleAvailable("@" + normalized), systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundColor(AppTheme.color(for: .support02, theme: theme))
        case .unavailable(let reason):
            Label(reason, systemImage: "xmark.circle.fill")
                .font(.footnote)
                .foregroundColor(AppTheme.color(for: .support05, theme: theme))
        }
    }

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.socialConfirmPrompt("@" + viewModel.claimedHandle))
                .font(.headline)
            TextField(L10n.socialDisplayNamePlaceholder, text: $viewModel.displayNameInput)
                .padding(12)
                .background(AppTheme.color(for: .primaryUi02, theme: theme))
                .cornerRadius(8)
            Text(L10n.socialConfirmPrivateNote)
                .font(.footnote)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            if let error = viewModel.joinError {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(AppTheme.color(for: .support05, theme: theme))
            }
            Spacer()
            Button(action: { Task { await viewModel.join() } }) {
                if viewModel.isJoining {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text(L10n.socialJoinCta).frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(RoundedButtonStyle(theme: theme))
            .disabled(viewModel.isJoining || viewModel.displayNameInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
        .navigationTitle(L10n.socialJoinTitle)
        .toolbar { cancelItem }
    }

    private var cancelItem: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(L10n.cancel) { viewModel.cancel() }
        }
    }
}

@MainActor
final class SocialJoinViewModel: ObservableObject {
    enum Step { case terms, handle, confirm, privacyNudge }
    enum AvailabilityDisplay: Equatable {
        case idle, checking
        case available(normalized: String)
        case unavailable(reason: String)
    }

    /// The public-identity terms revision recorded at join (ADR-0005).
    static let termsVersion = 1

    @Published var step: Step = .terms
    @Published var handleInput: String = "" { didSet { scheduleAvailabilityCheck() } }
    @Published var displayNameInput: String = ""
    @Published private(set) var availability: SocialHandleAvailability = .unknown
    @Published private(set) var availabilityDisplay: AvailabilityDisplay = .idle
    @Published private(set) var isJoining = false
    @Published private(set) var joinError: String?

    private(set) var claimedHandle: String = ""
    private(set) var joinedProfile: SocialProfile?
    private var checkTask: Task<Void, Never>?
    private let onFinished: (SocialProfile?) -> Void

    init(onFinished: @escaping (SocialProfile?) -> Void) {
        self.onFinished = onFinished
    }

    func acceptTerms() {
        step = .handle
    }

    func confirmHandle() {
        guard availability.isClaimable else { return }
        claimedHandle = Self.normalize(handleInput)
        // Seed the display name from the device-local Share Profile content
        // (decision 9: content only, never its toggles).
        if displayNameInput.isEmpty {
            displayNameInput = UserDefaults.standard.string(forKey: "ShareProfileDisplayName") ?? ""
        }
        step = .confirm
    }

    func join() async {
        isJoining = true
        joinError = nil
        let profile = await ApiServerHandler.shared.joinSocial(handle: claimedHandle,
                                                               displayName: displayNameInput.trimmingCharacters(in: .whitespaces),
                                                               termsVersion: Self.termsVersion)
        isJoining = false
        guard let profile else {
            joinError = L10n.socialJoinFailed
            return
        }
        SocialIdentityStore.cachedProfile = profile
        joinedProfile = profile
        Analytics.track(.socialProfileJoined)
        step = .privacyNudge
    }

    func finish() {
        onFinished(joinedProfile)
    }

    func cancel() {
        onFinished(nil)
    }

    // MARK: - Availability

    private static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "@", with: "")
    }

    private func scheduleAvailabilityCheck() {
        checkTask?.cancel()
        let candidate = Self.normalize(handleInput)
        guard !candidate.isEmpty else {
            availability = .unknown
            availabilityDisplay = .idle
            return
        }
        availabilityDisplay = .checking
        checkTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, let self else { return }
            let (status, normalized) = await ApiServerHandler.shared.checkHandleAvailability(candidate)
            guard !Task.isCancelled, Self.normalize(self.handleInput) == candidate else { return }
            self.availability = status
            switch status {
            case .available:
                self.availabilityDisplay = .available(normalized: normalized)
            case .taken:
                self.availabilityDisplay = .unavailable(reason: L10n.socialHandleTaken)
            case .reserved, .tombstoned:
                self.availabilityDisplay = .unavailable(reason: L10n.socialHandleReserved)
            case .invalid:
                self.availabilityDisplay = .unavailable(reason: L10n.socialHandleInvalid)
            case .unknown:
                self.availabilityDisplay = .unavailable(reason: L10n.socialHandleCheckFailed)
            }
        }
    }
}

// MARK: - One-time announcement

/// The one-time social announcement sheet (grill decision: CTA row + one-time
/// prompt). Shown at most once per device; never re-shown after dismissal.
enum SocialAnnouncement {
    static let shownKey = "SocialAnnouncementShown"

    static var shouldShow: Bool {
        FeatureFlag.socialProfiles.enabled
            && SyncManager.isUserLoggedIn()
            && !SocialIdentityStore.isJoined
            && !UserDefaults.standard.bool(forKey: shownKey)
    }

    static func markShown() {
        UserDefaults.standard.set(true, forKey: shownKey)
    }
}

struct SocialAnnouncementView: View {
    @EnvironmentObject var theme: Theme
    let onJoin: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "at.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(AppTheme.color(for: .primaryIcon01, theme: theme))
            Text(L10n.socialAnnouncementTitle)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(L10n.socialAnnouncementBody)
                .multilineTextAlignment(.center)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            Button(action: onJoin) {
                Text(L10n.socialAnnouncementCta)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(RoundedButtonStyle(theme: theme))
            Button(action: onDismiss) {
                Text(L10n.maybeLater)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            }
        }
        .padding(24)
        .background(AppTheme.color(for: .primaryUi01, theme: theme).ignoresSafeArea())
    }
}
