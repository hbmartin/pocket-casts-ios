import Foundation
import PocketCastsUtils
import Testing
@testable import podcasts

@Suite("Inbound action routing", .tags(.integration, .inboundRouting))
struct InboundActionRoutingTests {
    struct RouteCase: Sendable, CustomTestStringConvertible {
        let url: URL
        let expectedAction: InboundAction

        var testDescription: String { url.absoluteString }
    }

    static let routeCases: [RouteCase] = [
        RouteCase(
            url: URL(string: "thcast://discover/?source=widget")!,
            expectedAction: .route(URL(string: "thcast://discover/?source=widget")!)
        ),
        RouteCase(
            url: URL(fileURLWithPath: "/tmp/subscriptions.opml"),
            expectedAction: .importOpml(URL(fileURLWithPath: "/tmp/subscriptions.opml"))
        ),
        RouteCase(
            url: URL(fileURLWithPath: "/tmp/subscriptions.xml"),
            expectedAction: .importOpml(URL(fileURLWithPath: "/tmp/subscriptions.xml"))
        ),
        RouteCase(
            url: URL(fileURLWithPath: "/tmp/export.pcasts"),
            expectedAction: .importArchive(URL(fileURLWithPath: "/tmp/export.pcasts"))
        ),
        RouteCase(
            url: URL(fileURLWithPath: "/tmp/episode.mp3"),
            expectedAction: .uploadMedia(URL(fileURLWithPath: "/tmp/episode.mp3"))
        ),
        // Text now routes to Read Aloud when the flag is on (it is, outside the
        // App Store). The two cases below are the ones that must never move: a
        // subscription list is still an import, not a narration.
        RouteCase(
            url: URL(fileURLWithPath: "/tmp/readme.txt"),
            expectedAction: FeatureFlag.readAloud.enabled
                ? .readAloudText(URL(fileURLWithPath: "/tmp/readme.txt"))
                : .unsupported
        ),
        RouteCase(
            url: URL(fileURLWithPath: "/tmp/essay.md"),
            expectedAction: FeatureFlag.readAloud.enabled
                ? .readAloudText(URL(fileURLWithPath: "/tmp/essay.md"))
                : .unsupported
        ),
        RouteCase(
            url: URL(string: "https://example.test/not-an-app-route")!,
            expectedAction: .unsupported
        )
    ]

    @Test("Classifies external URLs", arguments: routeCases)
    func classifiesExternalURL(routeCase: RouteCase) throws {
        let sandbox = try IntegrationTestSandbox()
        defer { try? sandbox.cleanUp() }

        #expect(sandbox.dataManager.podcastCount() == 0)
        #expect(InboundActionRouter.action(for: routeCase.url) == routeCase.expectedAction)
    }

    /// OPML and XML conform to `public.text` but not `public.plain-text`, so
    /// widening the router for narration cannot capture a subscription list.
    /// Pinned because getting it wrong would silently narrate someone's feeds.
    @Test("Subscription lists still import even with Read Aloud on")
    func opmlIsNeverNarrated() throws {
        let sandbox = try IntegrationTestSandbox()
        defer { try? sandbox.cleanUp() }

        for name in ["subscriptions.opml", "subscriptions.xml"] {
            let url = URL(fileURLWithPath: "/tmp/\(name)")
            #expect(InboundActionRouter.action(for: url) == .importOpml(url))
        }
    }

    @Test("Extracts valid shortcut URLs and rejects malformed values")
    func extractsShortcutURLs() throws {
        let sandbox = try IntegrationTestSandbox()
        defer { try? sandbox.cleanUp() }

        #expect(
            InboundActionRouter.shortcutURL(from: "thcast://shortcuts/discover")
                == URL(string: "thcast://shortcuts/discover")
        )
        #expect(InboundActionRouter.shortcutURL(from: nil) == nil)
        #expect(sandbox.directoryURL.deletingLastPathComponent().lastPathComponent == "PocketCastsIntegrationTests")
    }
}

extension Tag {
    @Tag static var inboundRouting: Self
}
