import Foundation
import Combine
import PocketCastsServer
import PocketCastsDataModel

/// Represents a view that will display information about the users profile such as email, subscription status, and stats
@MainActor
class ProfileDataViewModel: ObservableObject {

    // Allow UIKit to update to view size changes
    private(set) var contentSize: CGSize? = nil
    var viewContentSizeChanged: (() -> Void)? = nil

    /// The user profile information such as logged in, email, etc
    var profile: UserInfo.Profile = .init()

    /// Listening Stats
    var stats: UserInfo.Stats = .init()

    private var refreshedToken: NotificationCenter.ObservationToken?

    init() {
        update()

        // Listen for the refresh event to update the view
        refreshedToken = NotificationCenter.default.addObserver(for: PodcastsRefreshed.self) { [weak self] _ in
            self?.update()
        }
    }

    deinit {
        // Property reads must precede any call that copies self; a plain deinit
        // may read stored state directly (Swift 6.2 isolated-deinit rule).
        let token = refreshedToken
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }

    /// Refresh the store data
    func update() {
        profile = .init()
        stats = .init()

        objectWillChange.send()
    }

    func contentSizeChanged(_ size: CGSize) {
        contentSize = size
        viewContentSizeChanged?()
    }
}
