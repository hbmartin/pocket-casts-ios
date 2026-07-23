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

/// Coordinates a single asset request without moving `NLContextualEmbedding`
/// (which is not `Sendable`) out of its owning provider actor.
actor ContextualEmbeddingAssetRequestGate {
    enum Admission: Sendable {
        case leader(UUID)
        case result(Bool)
    }

    private var cachedResult: Bool?
    private var requestID: UUID?
    private var waiters: [CheckedContinuation<Bool, Never>] = []

    func admission() async -> Admission {
        if let cachedResult {
            return .result(cachedResult)
        }

        if requestID != nil {
            let result = await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
            return .result(result)
        }

        let requestID = UUID()
        self.requestID = requestID
        return .leader(requestID)
    }

    func complete(requestID: UUID, assetsAvailable: Bool) {
        guard self.requestID == requestID else { return }

        self.requestID = nil
        cachedResult = assetsAvailable
        let waiters = self.waiters
        self.waiters.removeAll()
        waiters.forEach { $0.resume(returning: assetsAvailable) }
    }

    var waitingCallerCount: Int {
        waiters.count
    }
}

/// Wraps `NLContextualEmbedding`: one model per launch (chosen from the first
/// caller's language hint, defaulting to English's script), asset download
/// requests deduplicated while in flight, and load and inference serialized by
/// the actor. The first completed asset outcome is remembered for the launch;
/// when assets are unavailable semantic features silently degrade to FTS-only
/// and retry next launch.
actor ContextualEmbeddingProvider: TextEmbeddingProviding {
    static let shared = ContextualEmbeddingProvider()

    private var embedding: NLContextualEmbedding?
    private let assetRequestGate = ContextualEmbeddingAssetRequestGate()
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

        guard await assetsAreAvailable(for: embedding) else { return nil }

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

    private func assetsAreAvailable(for embedding: NLContextualEmbedding) async -> Bool {
        switch await assetRequestGate.admission() {
        case .result(let assetsAvailable):
            return assetsAvailable
        case .leader(let requestID):
            let assetsAvailable: Bool
            if embedding.hasAvailableAssets {
                assetsAvailable = true
            } else {
                assetsAvailable = await requestAssets(for: embedding)
            }
            await assetRequestGate.complete(requestID: requestID, assetsAvailable: assetsAvailable)
            if !assetsAvailable {
                Analytics.track(.transcriptEmbeddingAssetsUnavailable)
            }
            return assetsAvailable
        }
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
