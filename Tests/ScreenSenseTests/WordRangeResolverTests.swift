import XCTest
@testable import ScreenSenseCore

final class WordRangeResolverTests: XCTestCase {
    func testTokenizationPreservesCasingAndPunctuation() {
        let text = "Hello, world! Welcome to ScreenSense."
        let tokens = WordRangeResolver.tokenizeWords(in: text)

        XCTAssertEqual(tokens.count, 5)
        XCTAssertEqual(tokens[0].text, "Hello,")
        XCTAssertEqual(tokens[1].text, "world!")
        XCTAssertEqual(tokens[2].text, "Welcome")
        XCTAssertEqual(tokens[3].text, "to")
        XCTAssertEqual(tokens[4].text, "ScreenSense.")
    }

    func testExtractSubrangePreservesOriginalStringSubstring() {
        let text = "The Quick Brown Fox jumps over the lazy dog."
        // words 2 to 4 -> "Quick Brown Fox"
        let result = WordRangeResolver.extractWords(from: text, range: WordRange(start: 2, end: 4))

        switch result {
        case .success(let extracted):
            XCTAssertEqual(extracted, "Quick Brown Fox")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testExtractFirstWordAndLastWord() {
        let text = "First word and last word."

        // Word 1
        let firstResult = WordRangeResolver.extractWords(from: text, range: WordRange(start: 1, end: 1))
        if case .success(let first) = firstResult {
            XCTAssertEqual(first, "First")
        } else {
            XCTFail("Expected success for first word")
        }

        // Words 1 to 5
        let allResult = WordRangeResolver.extractWords(from: text, range: WordRange(start: 1, end: 5))
        if case .success(let all) = allResult {
            XCTAssertEqual(all, "First word and last word.")
        } else {
            XCTFail("Expected success for all words")
        }
    }

    func testOutOfBoundsAndReversedRange() {
        let text = "Short sentence."

        // Out of bounds (e.g. word 10)
        let outOfBounds = WordRangeResolver.extractWords(from: text, range: WordRange(start: 1, end: 10))
        if case .failure = outOfBounds {
            // Success
        } else {
            XCTFail("Expected failure for out of bounds range")
        }

        // Reversed range (start > end)
        let reversed = WordRangeResolver.extractWords(from: text, range: WordRange(start: 5, end: 2))
        if case .failure = reversed {
            // Success
        } else {
            XCTFail("Expected failure for reversed range")
        }
    }

    func testExtractTextBetweenDelimiters() {
        let text = "Deliver packages from Amazon to India with ultra-fast logistics."
        let range = TextRange(startText: "Amazon", endText: "India")

        let result = WordRangeResolver.extractTextRange(from: text, range: range)
        switch result {
        case .success(let extracted):
            XCTAssertEqual(extracted, "Amazon to India")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testExtractTextBetweenDelimitersNotFound() {
        let text = "Deliver packages from Apple to California."
        let range = TextRange(startText: "Amazon", endText: "India")

        let result = WordRangeResolver.extractTextRange(from: text, range: range)
        if case .failure = result {
            // Success
        } else {
            XCTFail("Expected failure when delimiter not found")
        }
    }
}
