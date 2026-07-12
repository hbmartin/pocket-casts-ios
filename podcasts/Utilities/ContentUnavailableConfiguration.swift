import SwiftUI
import UIKit

// Bespoke states stay SwiftUI-hosted until their native UIKit equivalents have exact visual parity.
@MainActor
struct ContentUnavailableConfiguration {
    struct Action {
        let title: String
        let handler: () -> Void

        init(title: String, handler: @escaping () -> Void) {
            self.title = title
            self.handler = handler
        }
    }

    static func loading() -> UIContentConfiguration {
        return UIHostingConfiguration {
            LoadingView().environmentObject(Theme.sharedTheme)
        }
    }

    static func noNetwork(tryAgainHandler: @escaping () -> Void) -> UIContentConfiguration {
        return UIHostingConfiguration {
            NoNetworkView(tryAgainHandler: tryAgainHandler).environmentObject(Theme.sharedTheme)
        }
    }

    static func noResults() -> UIContentConfiguration {
        return UIHostingConfiguration {
            NoResultsView().environmentObject(Theme.sharedTheme)
        }
    }

    static func empty() -> UIContentConfiguration {
        return UIHostingConfiguration {
            EmptyView()
        }
    }

    /// Returns a UIKit-backed empty state using the current theme colors.
    ///
    /// Callers must recreate the configuration when the app theme changes because
    /// UIKit content configurations do not observe `Theme` updates like the
    /// SwiftUI-hosted empty states do.
    static func nativeEmptyState(
        title: String,
        message: String?,
        image: UIImage?,
        action: Action? = nil,
        theme: Theme = .sharedTheme
    ) -> UIContentConfiguration {
        var configuration = UIKit.UIContentUnavailableConfiguration.empty()
        configuration.text = title
        configuration.secondaryText = message
        configuration.image = image?.withRenderingMode(.alwaysTemplate)
        configuration.imageProperties.tintColor = UIColor(AppTheme.color(for: .primaryIcon01, theme: theme))
        let iconSize = UIFontMetrics(forTextStyle: .headline).scaledValue(for: 30)
        configuration.imageProperties.maximumSize = CGSize(width: iconSize, height: iconSize)
        configuration.textProperties.color = UIColor(AppTheme.color(for: .primaryText01, theme: theme))
        configuration.secondaryTextProperties.color = UIColor(AppTheme.color(for: .primaryText02, theme: theme))

        if let action {
            var button = UIButton.Configuration.borderedProminent()
            button.title = action.title
            button.baseBackgroundColor = UIColor(AppTheme.color(for: .primaryInteractive01, theme: theme))
            button.baseForegroundColor = UIColor(AppTheme.color(for: .primaryInteractive02, theme: theme))
            configuration.button = button
            configuration.buttonProperties.primaryAction = UIAction { _ in
                action.handler()
            }
        }

        return configuration
    }

    static func emptyState<Style: EmptyStateViewStyle>(
        title: String,
        message: String?,
        icon: (() -> Image)? = nil,
        actions: [EmptyStateAction] = [],
        style: Style = DefaultEmptyStateStyle.defaultStyle
    ) -> UIContentConfiguration {
        return UIHostingConfiguration {
            EmptyStateView(title: title, message: message, icon: icon, actions: actions, style: style)
                .environmentObject(Theme.sharedTheme)
        }
    }
}

struct LoadingView: View {
    @EnvironmentObject private var theme: Theme
    var body: some View {
        VStack {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .padding()
                .tint(theme.primaryIcon01)
        }
    }
}

struct NoNetworkView: View {
    let tryAgainHandler: () -> Void

    @EnvironmentObject private var theme: Theme

    var body: some View {
        VStack(spacing: 16) {
            Image(decorative: "discover_nointernet")
            VStack(spacing: 10) {
                Text(L10n.discoverUnableToLoad)
                    .font(Font.system(size: 17))
                Text(L10n.checkInternetConnection)
                    .font(Font.system(size: 14))
            }
            .foregroundStyle(theme.primaryText01)
            Button(L10n.tryAgain) {
                tryAgainHandler()
            }
            .font(Font.system(size: 15))
            .foregroundStyle(theme.primaryInteractive01)
        }
    }
}

struct NoResultsView: View {
    @EnvironmentObject private var theme: Theme

    var body: some View {
        VStack(spacing: 12) {
            Image(decorative: "discover_noresult")
            VStack(spacing: 10) {
                Text(L10n.discoverNoPodcastsFound)
                    .font(Font.system(size: 17))
                Text(L10n.discoverNoPodcastsFoundMsg)
                    .font(Font.system(size: 14))
            }
            .foregroundStyle(theme.primaryText01)
        }
    }
}
