import PocketCastsServer
import PocketCastsUtils
import SwiftUI

@MainActor
class StatusPageViewModel: ObservableObject {
    @Published var running = false

    @Published var hasRun = false
    @Published var serverDetails: String?

    var originDescription: String {
        switch ServerOriginPolicy.shared.state {
        case let .ready(origin): "Server origin: \(origin)"
        case .invalidBuildOrigin: ServerOriginPolicy.shared.blockingMessage ?? "Invalid server origin"
        case .reinstallRequired: ServerOriginPolicy.shared.blockingMessage ?? "Reinstall required"
        }
    }

    class Service: Identifiable {
        let title: String
        let description: String
        let failureMessage: String
        let urls: [String]
        let customTest: (() async -> Bool)?
        var status: Result = .idle

        init(title: String, description: String, failureMessage: String, urls: [String] = [], customTest: (() async -> Bool)? = nil) {
            self.title = title
            self.description = description
            self.failureMessage = failureMessage
            self.urls = urls
            self.customTest = customTest
        }

        enum Result {
            case success, failure, running, idle
        }
    }

    lazy var checks = [
        Service(
            title: L10n.settingsStatusInternet,
            description: L10n.settingsStatusInternetDescription,
            failureMessage: L10n.settingsStatusInternetFailureMessage,
            urls: [],
            customTest: nil
        ),
        Service(
            title: L10n.settingsStatusExpensiveNetwork,
            description: L10n.settingsStatusExpensiveNetworkDescription,
            failureMessage: L10n.settingsStatusExpensiveNetworkFailureMessage,
            urls: [],
            customTest: {
                NetworkUtils.shared.isConnectedToUnexpensiveConnection()
            }
        ),
        Service(
            title: "Podcast server origin",
            description: "The build origin is pinned on first launch and cannot change across app updates.",
            failureMessage: "Reinstall is required before this build can use its configured server.",
            urls: [],
            customTest: { ServerOriginPolicy.shared.isNetworkAllowed }
        ),
        Service(
            title: L10n.settingsStatusRefreshService,
            description: L10n.settingsStatusRefreshServiceDescription,
            failureMessage: "The configured podcast backend did not answer its liveness check.",
            urls: [ServerConstants.Urls.main() + "livez"],
            customTest: nil
        ),
        Service(
            title: L10n.settingsStatusAccountService,
            description: L10n.settingsStatusAccountServiceDescription,
            failureMessage: "The attested capability manifest is unavailable.",
            urls: [],
            customTest: { await ServerCapabilitiesClient.shared.load(force: true) != nil }
        ),
        Service(
            title: L10n.settingsStatusDiscover,
            description: L10n.settingsStatusDiscoverDescription,
            failureMessage: "Representative discover or generated-artwork routes failed.",
            urls: [ServerConstants.Urls.discover() + "ios/content_v3.json",
                   ServerConstants.Urls.discover() + "images/artwork/light/280/1.png"],
            customTest: nil
        )
    ]

    private lazy var networkUtils = NetworkUtils.shared

    @MainActor
    func run() {
        running = true

        Task {
            for service in checks {
                service.status = .running

                if networkUtils.isConnected() {
                    await test(service: service)
                } else {
                    service.status = .failure
                }

                // Force UI to update after a service is checked
                objectWillChange.send()
            }

            running = false
            hasRun = true
            if let capabilities = await ServerCapabilitiesClient.shared.load() {
                serverDetails = "Version \(capabilities.serverVersion) · App Attest \(capabilities.appAttestMode) · Avatar \(capabilities.features.avatar ? "on" : "off") · Folders \(capabilities.features.folderSuggestions ? "on" : "off") · Corpus \(capabilities.features.corpus ? "on" : "off")"
            }
        }
    }

    @MainActor
    private func test(service: Service) async {
        if let customTest = service.customTest {
            service.status = await customTest() ? .success : .failure
        } else if service.urls.isEmpty {
            service.status = .success
        } else {
            var responseCodes = [Int?]()

            for url in service.urls {
                if let url = URL(string: url) {
                    let status = await url.requestHTTPStatus()
                    responseCodes.append(status)
                }
            }

            // If any response code is different from 200, it's a failure
            service.status = responseCodes.contains(where: { $0 != 200 }) ? .failure : .success
        }
    }
}

private extension URL {
    func requestHTTPStatus() async -> Int? {
        do {
            let (_, response) = try await URLConnection(handler: URLSession.shared).send(request: URLRequest(url: self))
            return (response as? HTTPURLResponse)?.statusCode
        } catch {
            return nil
        }
    }
}
