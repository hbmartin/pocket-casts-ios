import UIKit
import SwiftUI
import PocketCastsUtils
import PocketCastsServer

@MainActor
class AppTheme {
    nonisolated private static let tintColor = UIColor(hex: "#F44336")

    nonisolated class func appTintColor() -> UIColor {
        AppTheme.tintColor
    }

    class func placeholderTextColor() -> UIColor {
        Theme.isDarkTheme() ? UIColor(hex: "#808892") : UIColor(hex: "#C7C7CD")
    }

    class func pcPlusRed() -> UIColor {
        ThemeColor.support05()
    }

    class func pcPlusGoldGradientDark() -> UIColor {
        UIColor(hex: "#feb525")
    }

    class func pcPlusGoldGradientLight() -> UIColor {
        UIColor(hex: "#fed745")
    }

    class func successGreen() -> UIColor {
        UIColor(hex: "#78D549")
    }

    class func episodeCellPlayedIndicatorColor() -> UIColor {
        Theme.isDarkTheme() ? UIColor.white : UIColor.black
    }

    // MARK: - Mini Player

    class func miniPlayerButtonColor() -> UIColor {
        Theme.isDarkTheme() ? UIColor.white : UIColor(hex: "#9097A3")
    }

    class func waitingForWifiColor() -> UIColor {
        Theme.isDarkTheme() ? UIColor(hex: "#525466") : UIColor(hex: "#B8C3C9")
    }

    // MARK: - Sync Buttons

    class func disabledButtonColor() -> UIColor {
        Theme.isDarkTheme() ? UIColor(hex: "#929292") : UIColor(hex: "#D9D9D9")
    }

    // MARK: - Discover

    class func imagePlaceHolderColor() -> UIColor {
        Theme.isDarkTheme() ? UIColor(hex: "#4F4F4F") : UIColor(hex: "#E0E6EA")
    }

    // MARK: - Podcast Page

    class func extraContentBorderColor() -> UIColor {
        Theme.isDarkTheme() ? UIColor(hex: "#3A3A3B") : UIColor(hex: "#E0E6EA")
    }

    // MARK: - Episode Card Message

    class func episodeMessageBorderColor(for theme: Theme.ThemeType? = nil) -> UIColor {
        (theme?.isDark ?? Theme.isDarkTheme()) ? UIColor(hex: "#979797") : UIColor(hex: "#DCE1E4")
    }

    class func episodeMessageBackgroundColor(for theme: Theme.ThemeType? = nil) -> UIColor {
        (theme?.isDark ?? Theme.isDarkTheme()) ? UIColor(hex: "#3A3A3B") : UIColor(hex: "#FBFBFB")
    }

    nonisolated class func switchDarkThemeDefaultColor() -> UIColor {
        UIColor(hex: "#CCCCCC")
    }

    class func appearanceShadowColor() -> UIColor {
        UIColor(red: 0, green: 0, blue: 0, alpha: 0.15)
    }

    class func uploadProgressBackgroundColor() -> UIColor {
        Theme.isDarkTheme() ? viewBackgroundColor() : UIColor(hex: "#F9FAF9")
    }

    class func userEpisodeNoArtworkColor() -> UIColor {
        UIColor(hex: "#8F97A4")
    }

    class func embeddedArtworkColor() -> UIColor {
        UIColor.black
    }

    class func defaultPodcastBackgroundColor() -> UIColor {
        UIColor(hex: "#1E1F1E")
    }

    class func podcastSearchBarStyle() -> UIBarStyle {
        switch Theme.sharedTheme.activeTheme {
        case .dark, .extraDark, .electric, .contrastDark:
            return UIBarStyle.black
        case .light, .classic, .indigo, .rosé, .contrastLight:
            return UIBarStyle.default
        }
    }

    // MARK: - Paid podcast colours

    class func podcastHeartDarkGradientColor() -> UIColor {
        UIColor(hex: "#A6A6A6")
    }

    class func podcastHeartLightGradientColor() -> UIColor {
        UIColor(hex: "#D5D5D5")
    }

    class func podcastHeartDarkRedGradientColor() -> UIColor {
        UIColor(hex: "#FF1100")
    }

    class func podcastHeartLightRedGradientColor() -> UIColor {
        UIColor(hex: "#AD0000")
    }

    class func supporterPodcastBackgroundColor() -> UIColor {
        UIColor(hex: "#616874")
    }

    // MARK: - Illustrations

    class func noFilesImageName() -> String {
        switch Theme.sharedTheme.activeTheme {
        case .light, .classic:
            return "no-files-light"
        case .dark, .extraDark:
            return "no-files-dark"
        case .electric:
            return "no-files-electric"
        case .indigo:
            return "no-files-indigo"
        case .rosé:
            return "no-files-rose"
        case .contrastLight:
            return "no-files-contrastLight"
        case .contrastDark:
            return "no-files-contrastDark"
        }
    }

    class func noConnectionImageName() -> String {
        switch Theme.sharedTheme.activeTheme {
        case .dark, .extraDark:
            return "no-connection-dark"
        case .light, .classic, .indigo:
            return "no-connection"
        case .electric:
            return "no-connection-electricity"
        case .rosé:
            return "no-connection-rose"
        case .contrastLight:
            return "no-connection-contrastLight"
        case .contrastDark:
            return "no-connection-contrastDark"
        }
    }

    class func setupNewAccountImageName() -> String {
        switch Theme.sharedTheme.activeTheme {
        case .dark, .extraDark:
            return "setup-new-account-dark"
        case .light, .classic:
            return "setup-new-account"
        case .electric:
            return "setup-new-account-electricity"
        case .indigo:
            return "setup-new-account-indigo"
        case .rosé:
            return "setup-new-account-rose"
        case .contrastLight:
            return "setup-new-account-contrastLight"
        case .contrastDark:
            return "setup-new-account-contrastDark"
        }
    }

    class func passwordChangedImageName() -> String {
        switch Theme.sharedTheme.activeTheme {
        case .dark, .extraDark:
            return "key-stars-dark"
        case .light, .classic:
            return "key-stars"
        case .electric:
            return "key-stars-electricity"
        case .indigo:
            return "key-stars-indigo"
        case .rosé:
            return "key-stars-rose"
        case .contrastLight:
            return "key-stars-contrastLight"
        case .contrastDark:
            return "key-stars-contrastDark"
        }
    }

    class func accountCreatedImageName() -> String {
        switch Theme.sharedTheme.activeTheme {
        case .dark, .extraDark:
            return "avatar-tick-dark"
        case .light, .classic:
            return "avatar-tick"
        case .electric:
            return "avatar-tick-electricity"
        case .indigo:
            return "avatar-tick-indigo"
        case .rosé:
            return "avatar-tick-rose"
        case .contrastLight:
            return "avatar-tick-contrastLight"
        case .contrastDark:
            return "avatar-tick-contrastDark"
        }
    }

    class func changedEmailImageName() -> String {
        switch Theme.sharedTheme.activeTheme {
        case .dark, .extraDark:
            return "email-stars-dark"
        case .light, .classic:
            return "email-stars"
        case .electric:
            return "email-stars-electricity"
        case .indigo:
            return "email-stars-indigo"
        case .rosé:
            return "email-stars-rose"
        case .contrastLight:
            return "email-stars-contrastLight"
        case .contrastDark:
            return "email-stars-contrastDark"
        }
    }

    class func pcLogoHorizontalImageName() -> String {
        switch Theme.sharedTheme.activeTheme {
        case .dark, .extraDark, .electric, .contrastDark:
            return "horizontal-logo-dark"
        case .light, .classic, .indigo, .rosé, .contrastLight:
            return "horizontal-logo"
        }
    }

    static func pcLogoSmallHorizontalImageName() -> String {
        switch Theme.sharedTheme.activeTheme {
        case .dark, .extraDark, .electric, .contrastDark, .indigo, .classic:
            return "small-horizontal-logo-dark"
        case .light, .rosé, .contrastLight:
            return "small-horizontal-logo"
        }
    }

    static func pcLogoSmallHorizontalForBackgroundImageName() -> String {
        switch Theme.sharedTheme.activeTheme {
        case .dark, .extraDark, .electric, .contrastDark:
            return "small-horizontal-logo-dark"
        case .light, .classic, .indigo, .rosé, .contrastLight:
            return "small-horizontal-logo"
        }
    }

    class func pcLogoVerticalImageName() -> String {
        switch Theme.sharedTheme.activeTheme {
        case .dark, .extraDark, .electric, .contrastDark:
            return "pc-logo-vertical-dark"
        case .light, .classic, .indigo, .rosé, .contrastLight:
            return "pc-logo-vertical"
        }
    }

    class func fileErrorImageName() -> String {
        switch Theme.sharedTheme.activeTheme {
        case .dark, .extraDark:
            return "fileError-dark"
        case .light, .classic:
            return "fileError"
        case .indigo:
            return "fileError-indigo"
        case .rosé:
            return "fileError-rose"
        case .electric:
            return "fileError-electricity"
        case .contrastLight:
            return "fileError-contrastLight"
        case .contrastDark:
            return "fileError-contrastDark"
        }
    }

    class func termsOfUseImageName() -> String {
        switch Theme.sharedTheme.activeTheme {
        case .dark, .extraDark:
            return "clipboard-dark"
        case .light, .classic:
            return "clipboard"
        case .electric:
            return "clipboard-electricity"
        case .indigo:
            return "clipboard-indigo"
        case .rosé:
            return "clipboard-rose"
        case .contrastLight:
            return "clipboard-contrastLight"
        case .contrastDark:
            return "clipboard-contrastDark"
        }
    }

    class func promoErrorImageName() -> String {
        switch Theme.sharedTheme.activeTheme {
        case .dark, .extraDark:
            return "promo-error-dark"
        case .light, .classic:
            return "promo-error"
        case .electric:
            return "promo-error-electricity"
        case .indigo:
            return "promo-error-indigo"
        case .rosé:
            return "promo-error-rose"
        case .contrastLight:
            return "promo-error-contrastLight"
        case .contrastDark:
            return "promo-error-contrastDark"
        }
    }

    class func emptyFilterImageName() -> String {
        switch Theme.sharedTheme.activeTheme {
        case .dark, .extraDark:
            return "empty-filter-dark"
        case .light, .classic:
            return "empty-filter"
        case .electric:
            return "empty-filter-electricity"
        case .indigo:
            return "empty-filter-indigo"
        case .rosé:
            return "empty-filter-rose"
        case .contrastLight:
            return "empty-filter-contrastLight"
        case .contrastDark:
            return "empty-filter-contrastDark"
        }
    }

    // MARK: - App Colors

    class func keyboardAppearance() -> UIKeyboardAppearance {
        Theme.isDarkTheme() ? UIKeyboardAppearance.dark : UIKeyboardAppearance.light
    }

    class func optionPickerBackgroundColor(for theme: Theme.ThemeType? = nil) -> UIColor {
        ThemeColor.primaryUi01(for: theme)
    }

    class func defaultStatusBarStyle() -> UIStatusBarStyle {
        switch Theme.sharedTheme.activeTheme {
        case .dark, .extraDark, .electric, .contrastDark:
            return UIStatusBarStyle.lightContent
        case .classic, .indigo:
            return UIStatusBarStyle.darkContent
        case .light, .rosé, .contrastLight:
            return UIStatusBarStyle.darkContent
        }
    }

    class func popupStatusBarStyle(themeOverride: Theme.ThemeType? = nil) -> UIStatusBarStyle {
        switch themeOverride ?? Theme.sharedTheme.activeTheme {
        case .dark, .extraDark, .electric, .contrastDark:
            return UIStatusBarStyle.lightContent
        case .light, .classic, .indigo, .rosé, .contrastLight:
            return UIStatusBarStyle.darkContent
        }
    }

    class func loadingActivityColor() -> UIColor {
        ThemeColor.primaryIcon01()
    }

    class func destructiveTextColor(for theme: Theme.ThemeType? = nil) -> UIColor {
        ThemeColor.support05(for: theme)
    }

    class func mainTextColor(for theme: Theme.ThemeType? = nil) -> UIColor {
        ThemeColor.primaryText01(for: theme)
    }

    class func tableDividerColor(for theme: Theme.ThemeType? = nil) -> UIColor {
        ThemeColor.primaryUi05(for: theme)
    }

    class func indicatorStyle(for theme: Theme.ThemeType? = nil) -> UIScrollView.IndicatorStyle {
        if let themeOverride = theme {
            return themeOverride.isDark ? .white : .black
        }
        return Theme.isDarkTheme() ? .white : .black
    }

    class func stepperColor() -> UIColor {
        ThemeColor.primaryInteractive01()
    }

    class func tabBarBackgroundColor() -> UIColor {
        ThemeColor.primaryUi03()
    }

    class func tabBarItemTintColor() -> UIColor {
        ThemeColor.primaryIcon02Selected()
    }

    class func unselectedTabBarItemColor() -> UIColor {
        ThemeColor.primaryIcon02()
    }

    class func navBarTitleColor(themeOverride: Theme.ThemeType? = nil) -> UIColor {
        ThemeColor.secondaryText01(for: themeOverride)
    }

    class func navBarIconsColor(themeOverride: Theme.ThemeType? = nil) -> UIColor {
        ThemeColor.secondaryIcon01(for: themeOverride)
    }

    class func viewBackgroundColor() -> UIColor {
        ThemeColor.primaryUi01()
    }

    class func userEpisodeColor(number: Int) -> UIColor {
        switch number {
        case 1:
            return userEpisodeNoArtworkColor()
        case 2:
            return userEpisodeRedColor()
        case 3:
            return userEpisodeBlueColor()
        case 4:
            return userEpisodeGreenColor()
        case 5:
            return userEpisodeYellowColor()
        case 6:
            return userEpisodeOrangeColor()
        case 7:
            return userEpisodePurpleColor()
        case 8:
            return userEpisodePinkColor()
        default:
            return userEpisodeNoArtworkColor()
        }
    }

    class func userEpisodeRedColor() -> UIColor {
        ThemeColor.filter01(for: Theme.isDarkTheme() ? .dark : .light)
    }

    class func userEpisodeBlueColor() -> UIColor {
        ThemeColor.filter05(for: Theme.isDarkTheme() ? .dark : .light)
    }

    class func userEpisodeGreenColor() -> UIColor {
        ThemeColor.filter04(for: Theme.isDarkTheme() ? .dark : .light)
    }

    class func userEpisodeYellowColor() -> UIColor {
        ThemeColor.filter03(for: Theme.isDarkTheme() ? .dark : .light)
    }

    class func userEpisodeOrangeColor() -> UIColor {
        ThemeColor.filter02(for: Theme.isDarkTheme() ? .dark : .light)
    }

    class func userEpisodePurpleColor() -> UIColor {
        ThemeColor.filter06(for: Theme.isDarkTheme() ? .dark : .light)
    }

    class func userEpisodePinkColor() -> UIColor {
        ThemeColor.filter07(for: Theme.isDarkTheme() ? .dark : .light)
    }

    class func folderColor(colorInt: Int32) -> UIColor {
        switch colorInt {
        case 0: return ThemeColor.filter01()
        case 1: return ThemeColor.filter02()
        case 2: return ThemeColor.filter03()
        case 3: return ThemeColor.filter04()
        case 4: return ThemeColor.filter05()
        case 5: return ThemeColor.filter06()
        case 6: return ThemeColor.filter07()
        case 7: return ThemeColor.filter08()
        case 8: return ThemeColor.filter09()
        case 9: return ThemeColor.filter10()
        case 10: return ThemeColor.filter11()
        case 11: return ThemeColor.filter12()
        default: return ThemeColor.filter08()
        }
    }

    class func playlistRedColor() -> UIColor {
        ThemeColor.filter01()
    }

    class func playlistBlueColor() -> UIColor {
        ThemeColor.filter05()
    }

    class func playlistGreenColor() -> UIColor {
        ThemeColor.filter04()
    }

    class func playlistPurpleColor() -> UIColor {
        ThemeColor.filter06()
    }

    class func playlistYellowColor() -> UIColor {
        ThemeColor.filter03()
    }

    // MARK: - Getting Colors from ThemeStyles

    /// Returns a SwiftUI color for the theme style
    nonisolated static func color(for style: ThemeStyle, theme: (any Theming)? = nil) -> Color {
        return colorForStyle(style, themeOverride: theme?.nonisolatedActiveTheme).color
    }

    /// Resolves a simple style through ThemeColorTable. The parameterized
    /// podcast*/playerBackground*/playerHighlight*/filter* families need a
    /// runtime colour and cannot be resolved here.
    nonisolated class func colorForStyle(_ style: ThemeStyle, themeOverride: Theme.ThemeType? = nil) -> UIColor {
        guard let token = style.simpleToken else {
            assertionFailure("**** colorForStyle: color token used that requires additional info, you cannot use this method to get this colour ****")
            return ThemeColor.primaryUi01(for: themeOverride)
        }
        return ThemeColorTable.color(token, for: themeOverride ?? Theme.sharedTheme.nonisolatedActiveTheme)
    }
}
