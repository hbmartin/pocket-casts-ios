import Foundation

/// Static description of a remote provider, for settings UI (picker rows) and
/// consent copy (URL-based vs upload-based wording).
public struct RemoteProviderInfo: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    /// True when the provider fetches the episode's public URL itself; false
    /// when the (transcoded) audio file is uploaded to the provider.
    public let supportsPublicURL: Bool
}

/// The single list of remote transcription providers: settings UI, consent gate
/// and the engine factory all resolve providers through here.
public enum RemoteProviderRegistry {
    public static let defaultProviderId = AssemblyAIProvider.providerId

    public static let providers: [RemoteProviderInfo] = [
        RemoteProviderInfo(id: AssemblyAIProvider.providerId, displayName: "AssemblyAI", supportsPublicURL: true),
        RemoteProviderInfo(id: DeepgramProvider.providerId, displayName: "Deepgram", supportsPublicURL: true),
        RemoteProviderInfo(id: OpenAIProvider.providerId, displayName: "OpenAI", supportsPublicURL: false),
        RemoteProviderInfo(id: ElevenLabsProvider.providerId, displayName: "ElevenLabs", supportsPublicURL: false),
        RemoteProviderInfo(id: GeminiProvider.providerId, displayName: "Google Gemini", supportsPublicURL: false),
    ]

    public static func info(id: String) -> RemoteProviderInfo? {
        providers.first { $0.id == id }
    }

    /// Instantiates the provider adapter for `id`, or nil for unknown ids
    /// (stale persisted setting).
    public static func makeProvider(id: String, session: URLSession = .shared) -> (any RemoteTranscriptionProvider)? {
        switch id {
        case AssemblyAIProvider.providerId: AssemblyAIProvider(session: session)
        case DeepgramProvider.providerId: DeepgramProvider(session: session)
        case OpenAIProvider.providerId: OpenAIProvider(session: session)
        case ElevenLabsProvider.providerId: ElevenLabsProvider(session: session)
        case GeminiProvider.providerId: GeminiProvider(session: session)
        default: nil
        }
    }
}

// MARK: - Key validation

/// Result of a lightweight "does this API key work" probe.
public enum RemoteKeyValidation: Sendable, Equatable {
    case valid
    case invalid
    /// The check itself failed (network trouble, unexpected status) — says
    /// nothing about the key.
    case indeterminate(String)
}

public extension RemoteProviderRegistry {
    /// Probes the cheapest authenticated GET each provider offers and maps the
    /// status: 2xx → `.valid`; 400/401/403 → `.invalid` (Gemini reports bad keys
    /// as 400 INVALID_ARGUMENT); anything else → `.indeterminate`.
    static func validateKey(providerId: String, apiKey: String, session: URLSession = .shared) async -> RemoteKeyValidation {
        guard let request = keyValidationRequest(providerId: providerId, apiKey: apiKey) else {
            return .indeterminate("Unknown provider")
        }

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .indeterminate("No HTTP response")
            }
            switch http.statusCode {
            case 200 ..< 300: return .valid
            case 400, 401, 403: return .invalid
            default: return .indeterminate("HTTP \(http.statusCode)")
            }
        } catch {
            return .indeterminate("Network unavailable")
        }
    }

    /// The per-provider validation probe. Internal-by-design return of a plain
    /// request keeps this testable without network.
    static func keyValidationRequest(providerId: String, apiKey: String) -> URLRequest? {
        var request: URLRequest
        switch providerId {
        case AssemblyAIProvider.providerId:
            request = URLRequest(url: URL(string: "https://api.assemblyai.com/v2/transcript?limit=1")!)
            request.setValue(apiKey, forHTTPHeaderField: "authorization")
        case DeepgramProvider.providerId:
            request = URLRequest(url: URL(string: "https://api.deepgram.com/v1/projects")!)
            request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        case OpenAIProvider.providerId:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case ElevenLabsProvider.providerId:
            request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/user")!)
            request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        case GeminiProvider.providerId:
            request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!)
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        default:
            return nil
        }
        return request
    }
}
