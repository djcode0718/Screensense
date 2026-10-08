import Foundation

/// Errors that can occur during word and text range resolution
public enum WordRangeError: Error, Equatable, Sendable {
    case emptySourceText
    case invalidRange(start: Int, end: Int, totalWords: Int)
    case startTextNotFound(String)
    case endTextNotFound(String)
    case textBoundsReversed
}

/// Token representing an individual word with its exact character range in source string
public struct WordToken: Equatable, Sendable {
    public let index: Int // 1-based index
    public let text: String
    public let charRange: Range<String.Index>

    public init(index: Int, text: String, charRange: Range<String.Index>) {
        self.index = index
        self.text = text
        self.charRange = charRange
    }
}

/// Deterministic resolver for word-based and text-to-text range extraction
public struct WordRangeResolver: Sendable {
    public init() {}

    /// Tokenizes a string into words preserving character indices
    public static func tokenizeWords(in text: String) -> [WordToken] {
        var tokens: [WordToken] = []
        var currentIndex = text.startIndex
        var wordNumber = 1

        while currentIndex < text.endIndex {
            // Skip leading whitespace
            while currentIndex < text.endIndex && text[currentIndex].isWhitespace {
                currentIndex = text.index(after: currentIndex)
            }

            guard currentIndex < text.endIndex else { break }

            let wordStart = currentIndex
            // Advance to end of word
            while currentIndex < text.endIndex && !text[currentIndex].isWhitespace {
                currentIndex = text.index(after: currentIndex)
            }
            let wordEnd = currentIndex

            let wordRange = wordStart..<wordEnd
            let wordText = String(text[wordRange])

            tokens.append(WordToken(index: wordNumber, text: wordText, charRange: wordRange))
            wordNumber += 1
        }

        return tokens
    }

    /// Extracts an exact substring for a 1-based word range (e.g. words 5 to 12)
    public static func extractWords(from sourceText: String, range: WordRange) -> Result<String, WordRangeError> {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.emptySourceText)
        }

        let tokens = tokenizeWords(in: sourceText)
        let totalWords = tokens.count

        guard range.start >= 1 && range.start <= totalWords && range.end >= range.start && range.end <= totalWords else {
            return .failure(.invalidRange(start: range.start, end: range.end, totalWords: totalWords))
        }

        let startIndex = range.start - 1
        let endIndex = range.end - 1

        let startCharRange = tokens[startIndex].charRange
        let endCharRange = tokens[endIndex].charRange

        let fullRange = startCharRange.lowerBound..<endCharRange.upperBound
        let extracted = String(sourceText[fullRange])

        return .success(extracted)
    }

    /// Extracts an exact substring between two text delimiters (e.g. from "Amazon" to "India")
    public static func extractTextRange(from sourceText: String, range: TextRange) -> Result<String, WordRangeError> {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.emptySourceText)
        }

        let lowerSource = sourceText.lowercased()
        let lowerStart = range.startText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerEnd = range.endText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        guard let startRange = lowerSource.range(of: lowerStart) else {
            return .failure(.startTextNotFound(range.startText))
        }

        // Search for end delimiter starting at or after start range
        let searchRemaining = lowerSource[startRange.lowerBound...]
        guard let endRange = searchRemaining.range(of: lowerEnd) else {
            return .failure(.endTextNotFound(range.endText))
        }

        let extractedRange = startRange.lowerBound..<endRange.upperBound
        let extracted = String(sourceText[extractedRange])

        return .success(extracted)
    }
}
