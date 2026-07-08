import SwiftUI
import UIKit

/// Allows for applying view modifiers to a SwiftUI View while also passing it into
/// the hosting controller without needing to use AnyView
///
/// Usage: See ThemedHostingController
class ModifedHostingController<Content: View, Modifier: ViewModifier>: UIHostingController<ModifedHostingController.Wrapper> where Content: View {
    init(rootView: Content, modifier: Modifier) {
        super.init(rootView: .init(content: rootView, modifier: modifier))
    }

    struct Wrapper: View {
        let content: Content
        let modifier: Modifier

        var body: some View {
            content.modifier(modifier)
        }
    }

    @MainActor dynamic required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Allows easy use of SwiftUI Views by setting the Theme environment object on them
/// Usage of this is:
/// class MyCoolController: ThemedHostingController<MyThemedView> {
///     init(customValue: String) {
///         super.init(rootView: MyThemedView())
///         or if you already have a theme...
///         super.init(rootView: MyThemedView(), theme: theme)
///     }
/// }
class ThemedHostingController<Content>: ModifedHostingController<Content, ThemedEnvironment> where Content: View {

    private var background: KeyPath<Theme, Color>?

    init(rootView: Content, theme: Theme = Theme.sharedTheme, background: KeyPath<Theme, Color>? = nil) {
        self.background = background
        super.init(rootView: rootView, modifier: ThemedEnvironment(theme: theme))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        themeDidChange()
        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: Constants.Notifications.themeChanged, object: nil)
    }

    @objc func themeDidChange() {
        if let background {
            view.backgroundColor = UIColor(Theme.sharedTheme[keyPath: background])
        } else {
            view.backgroundColor = .clear
        }
    }

    @MainActor dynamic required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class PCHostingController<Content>: ThemedHostingController<Content> where Content: View {
    override func viewDidLoad() {
        super.viewDidLoad()

        // here we can set appearance traits that only apply to our SwiftUI views, and won't bleed into other parts of the app like .appearance() would
        UITableView.appearance(whenContainedInInstancesOf: [PCHostingController.self]).backgroundColor = .clear
        UICollectionView.appearance(whenContainedInInstancesOf: [PCHostingController.self]).backgroundColor = .clear
        UITextView.appearance(whenContainedInInstancesOf: [PCHostingController.self]).backgroundColor = UIColor.clear
    }
}

struct ThemedEnvironment: ViewModifier {
    let theme: Theme
    func body(content: Content) -> some View {
        content.environmentObject(theme)
    }
}

extension View {
    func setupDefaultEnvironment(theme: Theme = Theme.sharedTheme) -> some View {
        self.modifier(ThemedEnvironment(theme: theme))
    }
}
