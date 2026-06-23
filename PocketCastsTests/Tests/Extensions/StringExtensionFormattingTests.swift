import XCTest
@testable import podcasts

/// Pure-logic tests for small `String` formatting extensions (no singletons / DB / UI):
/// `sentenceCased`, `sanitizedFileName()`, and `toSnakeCaseFromCamelCase()`.
final class StringExtensionFormattingTests: XCTestCase {

    // MARK: - sentenceCased

    func testSentenceCased_capitalizesOnlyFirstWord() {
        XCTAssertEqual("hello world".sentenceCased, "Hello world")
        XCTAssertEqual("multiple words here".sentenceCased, "Multiple words here")
    }

    func testSentenceCased_lowercasesTheRest() {
        XCTAssertEqual("HELLO WORLD".sentenceCased, "Hello world")
    }

    func testSentenceCased_singleWordAndEmpty() {
        XCTAssertEqual("swift".sentenceCased, "Swift")
        XCTAssertEqual("".sentenceCased, "")
    }

    // MARK: - sanitizedFileName

    func testSanitizedFileName_stripsInvalidCharacters() {
        XCTAssertEqual("my/file:name*?.mp3".sanitizedFileName(), "myfilename.mp3")
        XCTAssertEqual("a\\b<c>d|e\"f".sanitizedFileName(), "abcdef")
    }

    func testSanitizedFileName_keepsValidCharacters() {
        XCTAssertEqual("A normal file name.mp3".sanitizedFileName(), "A normal file name.mp3")
    }

    // MARK: - toSnakeCaseFromCamelCase

    func testToSnakeCase_convertsCamelCase() {
        XCTAssertEqual("ohHelloThere".toSnakeCaseFromCamelCase(), "oh_hello_there")
        XCTAssertEqual("helloWorld".toSnakeCaseFromCamelCase(), "hello_world")
    }

    func testToSnakeCase_handlesAcronyms() {
        XCTAssertEqual("helloJSONWorld".toSnakeCaseFromCamelCase(), "hello_json_world")
    }

    func testToSnakeCase_lowercasesAlreadyFlatStrings() {
        XCTAssertEqual("hello".toSnakeCaseFromCamelCase(), "hello")
        XCTAssertEqual("alreadyflat".toSnakeCaseFromCamelCase(), "alreadyflat")
    }
}
