import Foundation
import Testing
@testable import PocketCastsTranscription

struct RemoteProviderRegistryTests {
    @Test func listsAllFiveProvidersWithTransportFlags() {
        let byId = Dictionary(uniqueKeysWithValues: RemoteProviderRegistry.providers.map { ($0.id, $0) })

        #expect(RemoteProviderRegistry.providers.count == 5)
        #expect(byId["assemblyai"]?.supportsPublicURL == true)
        #expect(byId["deepgram"]?.supportsPublicURL == true)
        #expect(byId["openai"]?.supportsPublicURL == false)
        #expect(byId["elevenlabs"]?.supportsPublicURL == false)
        #expect(byId["gemini"]?.supportsPublicURL == false)
        #expect(RemoteProviderRegistry.defaultProviderId == "assemblyai")
    }

    @Test func makesProvidersMatchingTheirRegistryEntries() {
        for info in RemoteProviderRegistry.providers {
            let provider = RemoteProviderRegistry.makeProvider(id: info.id)
            #expect(provider?.id == info.id)
            #expect(provider?.displayName == info.displayName)
            #expect(provider?.supportsPublicURL == info.supportsPublicURL)
        }
        #expect(RemoteProviderRegistry.makeProvider(id: "not-a-provider") == nil)
    }

    @Test func validationRequestsCarryTheRightAuthHeaders() throws {
        let cases: [(id: String, host: String, header: String, value: String)] = [
            ("assemblyai", "api.assemblyai.com", "authorization", "k1"),
            ("deepgram", "api.deepgram.com", "Authorization", "Token k1"),
            ("openai", "api.openai.com", "Authorization", "Bearer k1"),
            ("elevenlabs", "api.elevenlabs.io", "xi-api-key", "k1"),
            ("gemini", "generativelanguage.googleapis.com", "x-goog-api-key", "k1"),
        ]

        for testCase in cases {
            let request = try #require(RemoteProviderRegistry.keyValidationRequest(providerId: testCase.id, apiKey: "k1"))
            #expect(request.url?.host == testCase.host)
            #expect(request.value(forHTTPHeaderField: testCase.header) == testCase.value)
        }
        #expect(RemoteProviderRegistry.keyValidationRequest(providerId: "nope", apiKey: "k1") == nil)
    }

    @Test func validateKeyMapsStatuses() async {
        let session = MockURLProtocol.makeSession()

        let validKey = "registry-valid-\(UUID().uuidString)"
        MockURLProtocol.register(apiKey: validKey) { _ in .json(#"{"transcripts": []}"#) }
        defer { MockURLProtocol.unregister(apiKey: validKey) }

        let invalidKey = "registry-invalid-\(UUID().uuidString)"
        MockURLProtocol.register(apiKey: invalidKey) { _ in .respond(statusCode: 401) }
        defer { MockURLProtocol.unregister(apiKey: invalidKey) }

        // Gemini reports bad keys as 400 INVALID_ARGUMENT.
        let badArgumentKey = "registry-badarg-\(UUID().uuidString)"
        MockURLProtocol.register(apiKey: badArgumentKey) { _ in .respond(statusCode: 400) }
        defer { MockURLProtocol.unregister(apiKey: badArgumentKey) }

        let flakyKey = "registry-flaky-\(UUID().uuidString)"
        MockURLProtocol.register(apiKey: flakyKey) { _ in .respond(statusCode: 503) }
        defer { MockURLProtocol.unregister(apiKey: flakyKey) }

        let offlineKey = "registry-offline-\(UUID().uuidString)"
        MockURLProtocol.register(apiKey: offlineKey) { _ in .fail(URLError(.notConnectedToInternet)) }
        defer { MockURLProtocol.unregister(apiKey: offlineKey) }

        #expect(await RemoteProviderRegistry.validateKey(providerId: "assemblyai", apiKey: validKey, session: session) == .valid)
        #expect(await RemoteProviderRegistry.validateKey(providerId: "openai", apiKey: invalidKey, session: session) == .invalid)
        #expect(await RemoteProviderRegistry.validateKey(providerId: "gemini", apiKey: badArgumentKey, session: session) == .invalid)
        #expect(await RemoteProviderRegistry.validateKey(providerId: "deepgram", apiKey: flakyKey, session: session) == .indeterminate("HTTP 503"))
        #expect(await RemoteProviderRegistry.validateKey(providerId: "elevenlabs", apiKey: offlineKey, session: session) == .indeterminate("Network unavailable"))
        #expect(await RemoteProviderRegistry.validateKey(providerId: "nope", apiKey: "k", session: session) == .indeterminate("Unknown provider"))
    }
}
