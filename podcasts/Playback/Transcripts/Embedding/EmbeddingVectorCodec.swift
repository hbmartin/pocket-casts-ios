import Foundation

/// Encoding between embedding vectors and the sidecar's stored blobs:
/// little-endian Float16, L2-normalized before encoding so cosine similarity
/// at query time is a plain dot product.
nonisolated enum EmbeddingVectorCodec {

    static let quantization = "float16"

    /// L2-normalizes (a zero vector stays zero) and encodes.
    static func encode(_ vector: [Float]) -> Data {
        let normalized = l2Normalized(vector)
        var data = Data(capacity: normalized.count * MemoryLayout<Float16>.size)
        for value in normalized {
            var half = Float16(value)
            withUnsafeBytes(of: &half) { data.append(contentsOf: $0) }
        }
        return data
    }

    static func decode(_ data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float16>.size
        var result = [Float](repeating: 0, count: count)
        data.withUnsafeBytes { raw in
            let halves = raw.bindMemory(to: Float16.self)
            for index in 0 ..< count {
                result[index] = Float(halves[index])
            }
        }
        return result
    }

    static func l2Normalized(_ vector: [Float]) -> [Float] {
        let magnitude = sqrt(vector.reduce(into: Float(0)) { $0 += $1 * $1 })
        guard magnitude > .ulpOfOne else { return vector }
        return vector.map { $0 / magnitude }
    }

    /// Dot product of a stored blob against an already-normalized query vector —
    /// cosine similarity, given both sides are normalized. Returns nil on
    /// dimension mismatch (a corrupt or foreign-model row must never score).
    static func dotProduct(_ data: Data, query: [Float]) -> Float? {
        let count = data.count / MemoryLayout<Float16>.size
        guard count == query.count, count > 0 else { return nil }
        return data.withUnsafeBytes { raw in
            let halves = raw.bindMemory(to: Float16.self)
            var total: Float = 0
            for index in 0 ..< count {
                total += Float(halves[index]) * query[index]
            }
            return total
        }
    }
}
