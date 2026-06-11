import Foundation

// ruleid: pocketcasts.no-zendesk-or-wordpress-integration
import ZendeskCoreSDK

enum RemovedSupportCredentials {
    // ruleid: pocketcasts.no-zendesk-or-wordpress-integration
    static let zendeskAPIKey = ""

    // ruleid: pocketcasts.no-zendesk-or-wordpress-integration
    static let zendeskUrl = ""

    // ruleid: pocketcasts.no-zendesk-or-wordpress-integration
    static let zendeskNewUrl = ""

    // ruleid: pocketcasts.no-zendesk-or-wordpress-integration
    static let dotcomSecret = ""
}

enum RemovedTranslationSources {
    // ruleid: pocketcasts.no-zendesk-or-wordpress-integration
    static let glotPress = "https://translate.wordpress.com/projects/pocket-casts/ios/"

    // ruleid: pocketcasts.no-zendesk-or-wordpress-integration
    static let releaseToolkit = "https://github.com/wordpress-mobile/release-toolkit"
}

enum AllowedSupportIntegration {
    // ok: pocketcasts.no-zendesk-or-wordpress-integration
    static let supportEmail = "support@pocketcasts.com"

    // ok: pocketcasts.no-zendesk-or-wordpress-integration
    static let helpCenter = "https://support.pocketcasts.com"
}
