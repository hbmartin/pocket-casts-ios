import UIKit

final class SceneHelperDefaultPresenterExamples {
    init(
        // ruleid: pocketcasts.scene-helper-root-presenter-default-argument
        presenter: UIViewController? = SceneHelper.rootViewController()
    ) {
        _ = presenter
    }

    func open(
        // ruleid: pocketcasts.scene-helper-root-presenter-default-argument
        _ presenter: UIViewController? = SceneHelper.rootViewController()
    ) {
        _ = presenter
    }

    func openSafely(presenter: UIViewController? = nil) {
        _ = presenter
    }

    func openWithEagerOption(url: URL) {
        // ruleid: pocketcasts.urlhelper-eager-root-presenter-option
        URLHelper.open(
            url,
            context: .externalContent,
            options: .init(
                presenter: SceneHelper.rootViewController(),
                prefersExternalBrowser: false
            )
        )
    }

    func openWithLazyOption(url: URL) {
        // ok: pocketcasts.urlhelper-eager-root-presenter-option
        URLHelper.open(
            url,
            context: .externalContent,
            options: .init(prefersExternalBrowser: false)
        )
    }

    func resolvePresenterLazily() {
        // ok: pocketcasts.scene-helper-root-presenter-default-argument
        let presenter = SceneHelper.rootViewController()
        _ = presenter
    }
}
