import Foundation

/// Deterministic parser for converting speech transcripts into actionable Commands
public final class DeterministicCommandParser: CommandParserProtocol {
    public init() {}

    public func parse(transcript: String) -> CommandParseResult {
        let normalized = StringNormalizer.normalize(transcript)

        ScreenSenseLogger.parser.debug("Parsing transcript: '\(transcript, privacy: .public)', normalized: '\(normalized, privacy: .public)'")

        if normalized.isEmpty {
            return .empty
        }

        // Check for Paste command patterns
        if isPasteCommand(normalized) {
            let pasteCmd = PasteCommand(rawTranscript: transcript, normalizedTranscript: normalized)
            return .success(command: pasteCmd.toAnyCommand())
        }

        // Check for Copy Element command patterns (heading, button, link, paragraph)
        if let copyCmd = parseCopyElementCommand(normalized, rawTranscript: transcript) {
            return .success(command: copyCmd.toAnyCommand())
        }

        return .unsupported(
            transcript: transcript,
            reason: "Command not recognized: \"\(transcript)\""
        )
    }

    private static let elementNounMap: [String: ElementType] = [
        "heading": .heading,
        "headings": .heading,
        "header": .heading,
        "headers": .heading,
        "title": .heading,
        "titles": .heading,
        "button": .button,
        "buttons": .button,
        "link": .link,
        "links": .link,
        "paragraph": .paragraph,
        "paragraphs": .paragraph
    ]

    private static let ordinalMap: [String: Int] = [
        "first": 1, "1st": 1, "one": 1, "1": 1,
        "second": 2, "2nd": 2, "two": 2, "2": 2,
        "third": 3, "3rd": 3, "three": 3, "3": 3,
        "fourth": 4, "4th": 4, "four": 4, "4": 4,
        "fifth": 5, "5th": 5, "five": 5, "5": 5,
        "sixth": 6, "6th": 6, "six": 6, "6": 6,
        "seventh": 7, "7th": 7, "seven": 7, "7": 7,
        "eighth": 8, "8th": 8, "eight": 8, "8": 8,
        "ninth": 9, "9th": 9, "nine": 9, "9": 9,
        "tenth": 10, "10th": 10, "ten": 10, "10": 10
    ]

    private func parseCopyElementCommand(_ normalized: String, rawTranscript: String) -> CopyElementCommand? {
        let words = normalized.components(separatedBy: " ").filter { !$0.isEmpty }
        let fillerWords: Set<String> = ["please", "hey", "can", "you", "just", "screensense", "now", "would", "could", "will", "do"]
        let cleanedWords = words.filter { !fillerWords.contains($0) }

        guard let first = cleanedWords.first, first == "copy" else { return nil }
        let tokens = Array(cleanedWords.dropFirst())
        guard !tokens.isEmpty else { return nil }

        let articles: Set<String> = ["the", "this", "that", "a", "an"]

        // Pattern 1: [NOUN] -> e.g. ["heading"], ["button"], ["link"], ["paragraph"]
        if tokens.count == 1, let type = Self.elementNounMap[tokens[0]] {
            return CopyElementCommand(rawTranscript: rawTranscript, normalizedTranscript: normalized, targetType: type, targetIndex: nil)
        }

        // Pattern 2: [ARTICLE, NOUN] -> e.g. ["the", "heading"], ["this", "button"]
        if tokens.count == 2, articles.contains(tokens[0]), let type = Self.elementNounMap[tokens[1]] {
            return CopyElementCommand(rawTranscript: rawTranscript, normalizedTranscript: normalized, targetType: type, targetIndex: nil)
        }

        // Pattern 3: [ORDINAL, NOUN] -> e.g. ["first", "heading"], ["2nd", "button"]
        if tokens.count == 2, let idx = Self.ordinalMap[tokens[0]], let type = Self.elementNounMap[tokens[1]] {
            return CopyElementCommand(rawTranscript: rawTranscript, normalizedTranscript: normalized, targetType: type, targetIndex: idx)
        }

        // Pattern 4: [ARTICLE, ORDINAL, NOUN] -> e.g. ["the", "first", "heading"], ["the", "2nd", "button"]
        if tokens.count == 3, articles.contains(tokens[0]), let idx = Self.ordinalMap[tokens[1]], let type = Self.elementNounMap[tokens[2]] {
            return CopyElementCommand(rawTranscript: rawTranscript, normalizedTranscript: normalized, targetType: type, targetIndex: idx)
        }

        // Pattern 5: [NOUN, ORDINAL] -> e.g. ["heading", "2"], ["button", "two"], ["link", "3"]
        if tokens.count == 2, let type = Self.elementNounMap[tokens[0]], let idx = Self.ordinalMap[tokens[1]] {
            return CopyElementCommand(rawTranscript: rawTranscript, normalizedTranscript: normalized, targetType: type, targetIndex: idx)
        }

        // Pattern 6: [ARTICLE, NOUN, ORDINAL] -> e.g. ["the", "heading", "2"], ["the", "link", "3"]
        if tokens.count == 3, articles.contains(tokens[0]), let type = Self.elementNounMap[tokens[1]], let idx = Self.ordinalMap[tokens[2]] {
            return CopyElementCommand(rawTranscript: rawTranscript, normalizedTranscript: normalized, targetType: type, targetIndex: idx)
        }

        // Pattern 7: [NOUN, "number", ORDINAL] -> e.g. ["heading", "number", "2"]
        if tokens.count == 3, tokens[1] == "number", let type = Self.elementNounMap[tokens[0]], let idx = Self.ordinalMap[tokens[2]] {
            return CopyElementCommand(rawTranscript: rawTranscript, normalizedTranscript: normalized, targetType: type, targetIndex: idx)
        }

        // Pattern 8: [ARTICLE, NOUN, "number", ORDINAL] -> e.g. ["the", "link", "number", "3"]
        if tokens.count == 4, articles.contains(tokens[0]), tokens[2] == "number", let type = Self.elementNounMap[tokens[1]], let idx = Self.ordinalMap[tokens[3]] {
            return CopyElementCommand(rawTranscript: rawTranscript, normalizedTranscript: normalized, targetType: type, targetIndex: idx)
        }

        return nil
    }

    private func isPasteCommand(_ normalized: String) -> Bool {
        // Direct matches
        let directMatches: Set<String> = [
            "paste",
            "paste here",
            "please paste",
            "please paste here",
            "paste this",
            "paste it",
            "paste at cursor",
            "can you paste",
            "just paste",
            "do paste"
        ]

        if directMatches.contains(normalized) {
            return true
        }

        // Substring / Prefix / Suffix matching for minor variations
        let words = normalized.components(separatedBy: " ").filter { !$0.isEmpty }

        // If it starts with polite words and has "paste" (e.g., "hey please paste", "screensense paste")
        let fillerWords: Set<String> = ["please", "hey", "can", "you", "just", "screensense", "now", "would", "could"]
        let cleanedWords = words.filter { !fillerWords.contains($0) }
        let cleanedPhrase = cleanedWords.joined(separator: " ")

        if directMatches.contains(cleanedPhrase) {
            return true
        }

        // If the core verb is just "paste" or "paste here"
        if cleanedWords == ["paste"] || cleanedWords == ["paste", "here"] || cleanedWords == ["paste", "this"] || cleanedWords == ["paste", "it"] {
            return true
        }

        return false
    }
}
