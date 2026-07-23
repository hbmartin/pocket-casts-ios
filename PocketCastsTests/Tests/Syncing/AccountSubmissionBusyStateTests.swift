import Testing
import UIKit

@testable import podcasts

@MainActor
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
