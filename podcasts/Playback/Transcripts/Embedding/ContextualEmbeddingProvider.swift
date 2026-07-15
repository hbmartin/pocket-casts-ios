import Foundation
import NaturalLanguage
import PocketCastsDataModel
import PocketCastsUtils

/// A text-embedding engine the pipeline can call, injectable for tests.
nonisolated protocol TextEmbeddingProviding: Sendable {
    /// The model's identity once its assets are loaded; nil when unavailable
    /// (device ineligible, assets not downloaded yet, download failed).
    func modelInfo() async -> TranscriptEmbeddingModelInfo?
    /// Mean-pooled, L2-normalized vectors, one per input text.
    func embed(texts: [String], languageHint: String?) async throws -> [[Float]]
}

enum TextEmbeddingError: Error {
    case assetsUnavailable
    case embeddingFailed
}

/// Wraps `NLContextualEmbedding`: one model per launch (chosen from the first
/// caller's language hint, defaulting to English's script), asset download
/// requested at most once per launch, load and inference serialized by the
/// actor. When assets are unavailable the provider stays dormant — semantic
/// features silently degrade to FTS-only and retry next launch.
actor ContextualEmbeddingProvider: TextEmbeddingProviding {
    static let shared = ContextualEmbeddingProvider()

    private var embedding: NLContextualEmbedding?
    /// nil = not asked yet; true/false = the remembered once-per-launch outcome.
    private var assetsAvailable: Bool?
    private var loaded = false

    func modelInfo() async -> TranscriptEmbeddingModelInfo? {
        guard let embedding = await readyEmbedding(languageHint: nil) else { return nil }
        return TranscriptEmbeddingModelInfo(
            identifier: embedding.modelIdentifier,
            revision: embedding.revision,
            dimension: embedding.dimension,
            quantization: EmbeddingVectorCodec.quantization
        )
    }

    func embed(texts: [String], languageHint: String?) async throws -> [[Float]] {
        guard let embedding = await readyEmbedding(languageHint: languageHint) else {
            throw TextEmbeddingError.assetsUnavailable
        }

        return try texts.map { text in
            let result = try embedding.embeddingResult(for: text, language: nil)
            var sum = [Double](repeating: 0, count: embedding.dimension)
            var tokenCount = 0
            result.enumerateTokenVectors(in: text.startIndex ..< text.endIndex) { vector, _ in
                for (index, value) in vector.enumerated() where index < sum.count {
                    sum[index] += value
                }
                tokenCount += 1
                return true
            }
            guard tokenCount > 0 else { throw TextEmbeddingError.embeddingFailed }
            let mean = sum.map { Float($0 / Double(tokenCount)) }
            return EmbeddingVectorCodec.l2Normalized(mean)
        }
    }

    // MARK: - Model lifecycle

    private func readyEmbedding(languageHint: String?) async -> NLContextualEmbedding? {
        if loaded, let embedding { return embedding }

        if embedding == nil {
            let language = Self.language(fromHint: languageHint)
            guard let model = NLContextualEmbedding(language: language) else {
                FileLog.shared.addMessage("[Embedding] no contextual embedding model for \(language.rawValue)")
                return nil
            }
            embedding = model
        }
        guard let embedding else { return nil }

        if assetsAvailable == nil {
            if embedding.hasAvailableAssets {
                assetsAvailable = true
            } else {
                assetsAvailable = await requestAssets(for: embedding)
                if assetsAvailable == false {
                    Analytics.track(.transcriptEmbeddingAssetsUnavailable)
                }
            }
        }
        guard assetsAvailable == true else { return nil }

        if !loaded {
            do {
                try embedding.load()
                loaded = true
            } catch {
                FileLog.shared.addMessage("[Embedding] model load failed: \(error)")
                return nil
            }
        }
        return embedding
    }

    private func requestAssets(for embedding: NLContextualEmbedding) async -> Bool {
        await withCheckedContinuation { continuation in
            embedding.requestAssets { result, error in
                if let error {
                    FileLog.shared.addMessage("[Embedding] asset request failed: \(error)")
                }
                continuation.resume(returning: result == .available)
            }
        }
    }

    static func language(fromHint hint: String?) -> NLLanguage {
        if let hint, !hint.isEmpty {
            // Hints are BCP-47 (e.g. "en-US"); NLLanguage wants the base code.
            let base = hint.split(separator: "-").first.map(String.init) ?? hint
            return NLLanguage(base)
        }
        return .english
    }
}
