import SwiftUI

/// View model for the header view that appears on the Profile tab view
class AccountHeaderViewModel: ProfileDataViewModel {
    @Published var viewState: ViewState = .freeAccount

    override func update() {
        super.update()
        viewState = .freeAccount
    }

    enum ViewState {
        case freeAccount
    }
}
