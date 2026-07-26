import Testing
import UIKit

@testable import podcasts
@testable import PocketCastsUtils

@MainActor
@Suite(.serialized)
struct AccountSubmissionBusyStateTests {
    @Test("Account creation remains non-reentrant when fields emit changes")
    func accountCreationBusyStateSurvivesFieldChanges() {
        let controller = NewEmailViewController()
        controller.loadViewIfNeeded()
        controller.emailField.text = "person@example.com"
        controller.passwordField.text = "password"

        controller.setBusy(true)
        controller.emailField.sendActions(for: .editingChanged)
        controller.passwordField.sendActions(for: .editingChanged)

        #expect(controller.isBusy)
        #expect(!controller.nextButton.isEnabled)
        #expect(!controller.contentView.isUserInteractionEnabled)
    }

    @Test("New account flow restores the Create Account title when busy state ends")
    func newAccountCreationRestoresPrimaryTitle() {
        assertRestoredPrimaryTitle(newFlowEnabled: true, expectedTitle: L10n.createAccount)
    }

    @Test("Legacy account flow restores the Next title when busy state ends")
    func legacyAccountCreationRestoresPrimaryTitle() {
        assertRestoredPrimaryTitle(newFlowEnabled: false, expectedTitle: L10n.next)
    }

    private func assertRestoredPrimaryTitle(newFlowEnabled: Bool, expectedTitle: String) {
        let featureFlags = FeatureFlagMock()
        defer { featureFlags.reset() }
        featureFlags.set(.newOnboardingAccountCreation, value: newFlowEnabled)
        let controller = NewEmailViewController()
        controller.loadViewIfNeeded()

        controller.setBusy(true)
        controller.setBusy(false)

        #expect(controller.nextButton.title(for: .normal) == expectedTitle)
    }

    @Test("Post-registration retry restores the Sign In title when busy state ends")
    func postRegistrationRetryRestoresSignInTitle() {
        let controller = NewEmailViewController()
        controller.loadViewIfNeeded()
        controller.showPostRegistrationSignInFailure(username: "person@example.com", password: "password")

        controller.setBusy(true)
        controller.setBusy(false)

        #expect(controller.nextButton.title(for: .normal) == L10n.signIn)
    }

    @Test("Password change remains non-reentrant when fields emit changes")
    func passwordChangeBusyStateSurvivesFieldChanges() {
        let controller = ChangePasswordViewController()
        controller.loadViewIfNeeded()
        controller.currentField.text = "current-password"
        controller.newField.text = "new-password"
        controller.confirmField.text = "new-password"

        controller.setBusy(true)
        controller.currentField.sendActions(for: .editingChanged)
        controller.newField.sendActions(for: .editingChanged)
        controller.confirmField.sendActions(for: .editingChanged)

        #expect(controller.isBusy)
        #expect(!controller.mainButton.isEnabled)
        #expect(!controller.contentView.isUserInteractionEnabled)
    }
}
