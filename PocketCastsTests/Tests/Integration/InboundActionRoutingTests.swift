import Foundation
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
        RouteCase(
            url: URL(fileURLWithPath: "/tmp/readme.txt"),
            expectedAction: .unsupported
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
