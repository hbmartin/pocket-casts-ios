import FoundationModels
import XCTest
@testable import podcasts

// MARK: - Mock provider

/// Serves a canned title (or failure) through the `IntelligenceProviding` seam.
nonisolated private struct MockIntelligence: IntelligenceProviding {
    var available = true
    var modelTitle: String?

    func availability() -> IntelligenceAvailability {
        available ? .available : .unavailable(reason: "device_not_eligible")
    }

    func respond<T: Generable & Sendable>(
        instructions: String,
        prompt: String,
        generating type: T.Type
    ) async throws -> T {
        guard let modelTitle, let output = GeneratedHighlightTitle(title: modelTitle) as? T else {
            throw IntelligenceError.generationFailed(description: "mock")
        }
        return output
    }
}

/// Auto-title generation for smart highlights: model-output validation, the
/// deterministic fallback, and the rename race guard
/// (plans/AI UX Improvements.md Phase 3).
final class HighlightTitleGeneratorTests: XCTestCase {
    // MARK: - Model path

    func testUsesValidatedModelTitleWhenAvailable() async {
        let generator = HighlightTitleGenerator(intelligence: MockIntelligence(modelTitle: "“A Sharp Observation”\n"))

        let title = await generator.title(for: "Some excerpt about a sharp observation.")

        XCTAssertEqual(title, "A Sharp Observation")
    }

    func testModelTitleIsHardCappedAtSixWords() async {
        let generator = HighlightTitleGenerator(intelligence: MockIntelligence(modelTitle: "one two three four five six seven eight"))

        let title = await generator.title(for: "Any excerpt.")

        XCTAssertEqual(title, "one two three four five six")
    }

    func testFallsBackWhenModelUnavailable() async {
        let generator = HighlightTitleGenerator(intelligence: MockIntelligence(available: false, modelTitle: "Should not be used"))

        let title = await generator.title(for: "The fallback sentence. And a second one.")

        XCTAssertEqual(title, "The fallback sentence")
    }

    func testFallsBackWhenGenerationThrows() async {
        let generator = HighlightTitleGenerator(intelligence: MockIntelligence(modelTitle: nil))

        let title = await generator.title(for: "Deterministic wins here. Extra.")

        XCTAssertEqual(title, "Deterministic wins here")
    }

    func testEmptyExcerptProducesNoTitle() async {
        let generator = HighlightTitleGenerator(intelligence: MockIntelligence(modelTitle: "Anything"))

        let title = await generator.title(for: "   \n ")

        XCTAssertNil(title)
    }

    // MARK: - Validation

    func testValidatedRejectsWhitespaceOnlyModelOutput() {
        XCTAssertNil(HighlightTitleGenerator.validated(modelTitle: " \n “” "))
    }

    // MARK: - Deterministic fallback

    func testFallbackUsesFirstSentence() {
        XCTAssertEqual(
            HighlightTitleGenerator.fallbackTitle(from: "Short and sweet. The rest is ignored entirely."),
            "Short and sweet"
        )
    }

    func testFallbackTruncatesLongSentenceOnWordBoundaryWithEllipsis() {
        let excerpt = "This opening sentence keeps going well past the fifty character budget before it ends."

        let title = HighlightTitleGenerator.fallbackTitle(from: excerpt)

        XCTAssertEqual(title, "This opening sentence keeps going well past the…")
        XCTAssertLessThanOrEqual(title?.count ?? 0, HighlightTitleGenerator.fallbackMaxLength + 1)
    }

    func testFallbackHandlesQuestionAndExclamationTerminators() {
        XCTAssertEqual(HighlightTitleGenerator.fallbackTitle(from: "Is this the moment? Yes."), "Is this the moment")
        XCTAssertEqual(HighlightTitleGenerator.fallbackTitle(from: "What a catch! Truly."), "What a catch")
    }

    func testFallbackReturnsNilForEmptyExcerpt() {
        XCTAssertNil(HighlightTitleGenerator.fallbackTitle(from: "  \n "))
    }

    // MARK: - Rename race guard

    func testAutoTitleOnlyAppliesToDefaultTitle() {
        XCTAssertTrue(HighlightEnricher.shouldApplyAutoTitle(currentTitle: L10n.bookmarkDefaultTitle))
        XCTAssertFalse(HighlightEnricher.shouldApplyAutoTitle(currentTitle: "My own name"))
        XCTAssertFalse(HighlightEnricher.shouldApplyAutoTitle(currentTitle: ""))
    }
}
