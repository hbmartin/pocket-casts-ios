import Foundation
import PocketCastsUtils

/// 🍞 Toast - A lightweight way to display informative overlay messages
///
/// Usage:
///
///     // Message only
///     Toast.show("Hello World!")
///
///     // Message with button
///     Toast.show("Hello", actions: [.init(title: "World", action: {
///          print("Hello World!")
///     })])
///
class Toast {
    @MainActor
    private static var shared = Toast()

    /// Retain the visible window
    private var window: UIWindow? = nil

    /// Display the toast message with the given title and actions.
    /// Callable from any thread (playback code shows toasts off-main); the window
    /// work hops to the main actor, so presentation is next-runloop.
    static func show(_ title: String, actions: [Action]? = nil, dismissAfter: ToastViewDismissPolicy = .interval(5.0), aboveMiniPlayer: Bool = false) {
        let box = PocketCastsUtils.UncheckedSendable(actions)
        Task { @MainActor in
            showOnMain(title, actions: box.value, dismissAfter: dismissAfter, theme: .defaultTheme, aboveMiniPlayer: aboveMiniPlayer)
        }
    }

    /// Variant with an explicit theme. Also callable from any thread; the theme
    /// object crosses to the main actor boxed.
    static func show<Style: ToastTheme>(_ title: String, actions: [Action]? = nil, dismissAfter: ToastViewDismissPolicy = .interval(5.0), theme: Style, aboveMiniPlayer: Bool = false) {
        let box = PocketCastsUtils.UncheckedSendable((actions, theme))
        Task { @MainActor in
            showOnMain(title, actions: box.value.0, dismissAfter: dismissAfter, theme: box.value.1, aboveMiniPlayer: aboveMiniPlayer)
        }
    }

    @MainActor
    private static func showOnMain<Style: ToastTheme>(_ title: String, actions: [Action]?, dismissAfter: ToastViewDismissPolicy, theme: Style, aboveMiniPlayer: Bool) {
        // Hide any active toasts
        shared.toastDismissed()

        guard let scene = SceneHelper.connectedScene() else { return }

        let viewModel = ToastViewModel(coordinator: shared, title: title, actions: actions, dismissPolicy: dismissAfter, aboveMiniPlayer: aboveMiniPlayer)
        let view = ToastView(viewModel: viewModel, style: theme)
        let controller = ThemedHostingController(rootView: view)

        let window = ToastWindow(windowScene: scene, viewModel: viewModel, controller: controller)
        window.makeKeyAndVisible()

        shared.window = window
    }

    /// Dismisses any visible toasts. Callable from any thread.
    static func dismiss() {
        Task { @MainActor in
            shared.window?.resignKey()
            shared.window = nil
        }
    }

    struct Action: Identifiable {
        let title: String
        let action: () -> Void

        var id: String { title }
    }
}

// MARK: - ToastCoordinator

extension Toast: ToastDelegate {
    func toastDismissed() {
        Self.dismiss()
    }
}

// MARK: - ToastWindow

/// This is a UIWindow subclass that allows passthrough events but also interaction with our SwiftUI toast view
/// The window overrides hitTest which asks the view model if the event point is within the view
private class ToastWindow: UIWindow {
    private weak var viewModel: ToastViewModel?

    init(windowScene: UIWindowScene, viewModel: ToastViewModel, controller: UIViewController) {
        self.viewModel = viewModel

        super.init(windowScene: windowScene)

        controller.view.backgroundColor = .clear
        rootViewController = controller
        windowLevel = .alert
        backgroundColor = .clear
    }

    // MARK: - Overridden

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        viewModel?.hitTest(point) ?? false ? super.hitTest(point, with: event) : nil
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
