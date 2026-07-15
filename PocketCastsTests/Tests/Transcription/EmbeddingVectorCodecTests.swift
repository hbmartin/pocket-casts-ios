import XCTest

@testable import podcasts

final class EmbeddingVectorCodecTests: XCTestCase {

    func testEncodeNormalizesAndRoundTrips() {
        let vector: [Float] = [3, 4, 0]
        let data = EmbeddingVectorCodec.encode(vector)
        XCTAssertEqual(data.count, 3 * MemoryLayout<Float16>.size)

        let decoded = EmbeddingVectorCodec.decode(data)
        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded[0], 0.6, accuracy: 0.01)
        XCTAssertEqual(decoded[1], 0.8, accuracy: 0.01)
        XCTAssertEqual(decoded[2], 0, accuracy: 0.001)

        let magnitude = sqrt(decoded.reduce(into: Float(0)) { $0 += $1 * $1 })
        XCTAssertEqual(magnitude, 1.0, accuracy: 0.01, "stored vectors are unit length")
    }

    func testZeroVectorSurvivesEncoding() {
        let decoded = EmbeddingVectorCodec.decode(EmbeddingVectorCodec.encode([0, 0]))
        XCTAssertEqual(decoded, [0, 0])
    }

    func testDotProductAgainstNormalizedQuery() {
        let stored = EmbeddingVectorCodec.encode([1, 0])
        XCTAssertEqual(EmbeddingVectorCodec.dotProduct(stored, query: [1, 0]) ?? -1, 1.0, accuracy: 0.01)
        XCTAssertEqual(EmbeddingVectorCodec.dotProduct(stored, query: [0, 1]) ?? -1, 0.0, accuracy: 0.01)

        let opposite = EmbeddingVectorCodec.encode([-1, 0])
        XCTAssertEqual(EmbeddingVectorCodec.dotProduct(opposite, query: [1, 0]) ?? 0, -1.0, accuracy: 0.01)
    }

    func testDotProductRejectsDimensionMismatch() {
        let stored = EmbeddingVectorCodec.encode([1, 0, 0])
        XCTAssertNil(EmbeddingVectorCodec.dotProduct(stored, query: [1, 0]))
        XCTAssertNil(EmbeddingVectorCodec.dotProduct(Data(), query: []))
    }
}
