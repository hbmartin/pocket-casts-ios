import XCTest

@testable import podcasts

final class EmbeddingVectorCodecTests: XCTestCase {

    func testEncodeNormalizesAndRoundTrips() throws {
        let vector: [Float] = [3, 4, 0]
        let data = EmbeddingVectorCodec.encode(vector)
        XCTAssertEqual(data.count, 3 * MemoryLayout<Float16>.size)

        let decoded = try XCTUnwrap(EmbeddingVectorCodec.decode(data))
        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded[0], 0.6, accuracy: 0.01)
        XCTAssertEqual(decoded[1], 0.8, accuracy: 0.01)
        XCTAssertEqual(decoded[2], 0, accuracy: 0.001)

        let magnitude = sqrt(decoded.reduce(into: Float(0)) { $0 += $1 * $1 })
        XCTAssertEqual(magnitude, 1.0, accuracy: 0.01, "stored vectors are unit length")
    }

    func testZeroVectorSurvivesEncoding() throws {
        let decoded = try XCTUnwrap(EmbeddingVectorCodec.decode(EmbeddingVectorCodec.encode([0, 0])))
        XCTAssertEqual(decoded, [0, 0])
    }

    func testDecodeReadsLittleEndianWordsFromMisalignedData() throws {
        var framed = Data([0xFF])
        framed.append(contentsOf: [0x00, 0x3C, 0x00, 0xC0]) // Float16 1.0, -2.0

        let misaligned = framed.dropFirst()
        XCTAssertTrue(misaligned.withUnsafeBytes { raw in
            guard let baseAddress = raw.baseAddress else { return false }
            return Int(bitPattern: baseAddress).isMultiple(of: MemoryLayout<Float16>.alignment) == false
        })
        XCTAssertEqual(try XCTUnwrap(EmbeddingVectorCodec.decode(misaligned)), [1, -2])
        XCTAssertEqual(
            try XCTUnwrap(EmbeddingVectorCodec.dotProduct(misaligned, query: [0.5, 0.25])),
            0,
            accuracy: 0.001
        )
    }

    func testDecodeAndDotProductRejectTruncatedWord() {
        let truncated = Data([0x00, 0x3C, 0xFF])

        XCTAssertNil(EmbeddingVectorCodec.decode(truncated))
        XCTAssertNil(EmbeddingVectorCodec.dotProduct(truncated, query: [1]))
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
