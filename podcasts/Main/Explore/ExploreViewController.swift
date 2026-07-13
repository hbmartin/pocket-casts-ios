import UIKit

/// Hosts the SwiftUI Explore screen as a main tab. `PCHostingController`
/// injects `Theme.sharedTheme` as an environment object.
class ExploreViewController: PCHostingController<ExploreView> {
    init() {
        super.init(rootView: ExploreView())

        title = L10n.exploreTabTitle
    }

    @MainActor dynamic required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
