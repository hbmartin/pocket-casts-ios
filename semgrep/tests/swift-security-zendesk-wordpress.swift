// Test fixture for pocketcasts.no-zendesk-or-wordpress-integration.
// The Zendesk support integration and the WordPress-hosted translation/credential
// sources were removed; these markers must not be reintroduced.

// ruleid: pocketcasts.no-zendesk-or-wordpress-integration
import ZendeskSDK

final class RemovedZendeskWordPressReferences {
    // ruleid: pocketcasts.no-zendesk-or-wordpress-integration
    let apiKey = ApiCredentials.zendeskAPIKey

    // ruleid: pocketcasts.no-zendesk-or-wordpress-integration
    let supportUrl = ApiCredentials.zendeskUrl

    // ruleid: pocketcasts.no-zendesk-or-wordpress-integration
    let newSupportUrl = ApiCredentials.zendeskNewUrl

    // ruleid: pocketcasts.no-zendesk-or-wordpress-integration
    let dotcom = ApiCredentials.dotcomSecret

    // The credential-template placeholders must not return either.
    // ruleid: pocketcasts.no-zendesk-or-wordpress-integration
    let templateApiKey = "%{zendesk_api_key}"
    // ruleid: pocketcasts.no-zendesk-or-wordpress-integration
    let templateUrl = "%{zendesk_url}"
    // ruleid: pocketcasts.no-zendesk-or-wordpress-integration
    let templateNewUrl = "%{zendesk_new_url}"
    // ruleid: pocketcasts.no-zendesk-or-wordpress-integration
    let templateDotcom = "%{dotcom_secret}"

    // ruleid: pocketcasts.no-zendesk-or-wordpress-integration
    let glotPressURL = "https://translate.wordpress.com/projects/pocket-casts/ios/"

    // ruleid: pocketcasts.no-zendesk-or-wordpress-integration
    let releaseToolkitLink = "https://github.com/wordpress-mobile/release-toolkit/pull/296"

    // GlotPress, Automattic ownership, and neutral URLs remain allowed.
    // ok: pocketcasts.no-zendesk-or-wordpress-integration
    let supportSite = ServerConstants.Urls.support
    // ok: pocketcasts.no-zendesk-or-wordpress-integration
    let glotPressProject = "pocket-casts/ios"
    // ok: pocketcasts.no-zendesk-or-wordpress-integration
    let neutralExternalURL = "https://example.com/"
    // ok: pocketcasts.no-zendesk-or-wordpress-integration
    let automatticOwned = "Automattic"
}
