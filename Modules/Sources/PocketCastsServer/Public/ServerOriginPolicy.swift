import Foundation

/// The immutable server origin selected by the installed build.
///
/// The first valid build origin is persisted in ordinary app-local settings.
/// If a later update changes it, server traffic is blocked until reinstall so
/// credentials and App Attest state can never cross origins accidentally.
public final class ServerOriginPolicy: Sendable {
    public enum State: Equatable, Sendable {
        case ready(origin: String)
        case invalidBuildOrigin(value: String?)
        case reinstallRequired(installed: String, build: String)
    }

    public static let shared = ServerOriginPolicy()
    public static let infoPlistKey = "PCPodcastBackendOrigin"
    public static let installedOriginDefaultsKey = "PCPodcastBackendInstalledOriginV1"
    static let debugEnvironmentKey = "POCKET_CASTS_SERVER_BASE_URL"

    public let state: State

    public var origin: URL? {
        guard case let .ready(value) = state else { return nil }
        return URL(string: value)
    }

    public var isNetworkAllowed: Bool {
        if case .ready = state { return true }
        return false
    }

    public var blockingMessage: String? {
        switch state {
        case .ready:
            nil
        case .invalidBuildOrigin:
            "This build does not contain a valid podcast server origin. Network access is disabled."
        case let .reinstallRequired(installed, build):
            "This update changed the podcast server from \(installed) to \(build). Reinstall the app to authorize the new origin. Offline playback remains available."
        }
    }

    public convenience init() {
        let environmentOverride: String?
        #if DEBUG && targetEnvironment(simulator)
        environmentOverride = ProcessInfo.processInfo.environment[Self.debugEnvironmentKey]
        #else
        environmentOverride = nil
        #endif

        self.init(
            buildOrigin: environmentOverride ?? Bundle.main.object(forInfoDictionaryKey: Self.infoPlistKey) as? String,
            defaults: .standard,
            allowInsecureLoopback: environmentOverride != nil
        )
    }

    init(buildOrigin: String?, defaults: UserDefaults, allowInsecureLoopback: Bool) {
        guard let normalized = Self.normalizedOrigin(buildOrigin, allowInsecureLoopback: allowInsecureLoopback) else {
            state = .invalidBuildOrigin(value: buildOrigin)
            return
        }

        if let installed = defaults.string(forKey: Self.installedOriginDefaultsKey) {
            state = installed == normalized
                ? .ready(origin: normalized)
                : .reinstallRequired(installed: installed, build: normalized)
        } else {
            defaults.set(normalized, forKey: Self.installedOriginDefaultsKey)
            state = .ready(origin: normalized)
        }
    }

    /// Valid origins contain only scheme, host and optional port. HTTPS is
    /// mandatory except for an explicit DEBUG simulator loopback override.
    static func normalizedOrigin(_ value: String?, allowInsecureLoopback: Bool) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              var components = URLComponents(string: value),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/"
        else {
            return nil
        }

        let scheme = components.scheme?.lowercased()
        let isLoopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
        guard scheme == "https" || (allowInsecureLoopback && scheme == "http" && isLoopback) else {
            return nil
        }

        components.scheme = scheme
        components.host = host
        components.path = "/"
        guard let url = components.url, url.path == "/" else { return nil }
        return url.absoluteString
    }
}

public enum ServerOriginError: LocalizedError, Sendable {
    case networkBlocked(String)

    public var errorDescription: String? {
        switch self {
        case let .networkBlocked(message): message
        }
    }
}
