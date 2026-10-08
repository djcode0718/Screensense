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

        // Check for Copy Paragraph command patterns
        if let copyCmd = parseCopyParagraphCommand(normalized, rawTranscript: transcript) {
            return .success(command: copyCmd.toAnyCommand())
        }

        return .unsupported(
            transcript: transcript,
            reason: "Command not recognized: \"\(transcript)\""
        )
    }

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

    private func parseCopyParagraphCommand(_ normalized: String, rawTranscript: String) -> CopyParagraphCommand? {
        let words = normalized.components(separatedBy: " ").filter { !$0.isEmpty }
        let fillerWords: Set<String> = ["please", "hey", "can", "you", "just", "screensense", "now", "would", "could", "will"]
        let cleanedWords = words.filter { !fillerWords.contains($0) }

        guard !cleanedWords.isEmpty else { return nil }

        // Generic single paragraph patterns: ["copy", "the", "paragraph"], ["copy", "paragraph"], ["copy", "this", "paragraph"], ["copy", "that", "paragraph"]
        if cleanedWords == ["copy", "the", "paragraph"] ||
           cleanedWords == ["copy", "paragraph"] ||
           cleanedWords == ["copy", "this", "paragraph"] ||
           cleanedWords == ["copy", "that", "paragraph"] {
            return CopyParagraphCommand(rawTranscript: rawTranscript, normalizedTranscript: normalized, targetIndex: nil)
        }

        // Pattern 1: ["copy", "the", "<ORDINAL>", "paragraph"]
        if cleanedWords.count == 4 && cleanedWords[0] == "copy" && cleanedWords[1] == "the" && cleanedWords[3] == "paragraph" {
            let ordinalKey = cleanedWords[2]
            if let index = Self.ordinalMap[ordinalKey] {
                return CopyParagraphCommand(rawTranscript: rawTranscript, normalizedTranscript: normalized, targetIndex: index)
            }
        }

        // Pattern 2: ["copy", "<ORDINAL>", "paragraph"]
        if cleanedWords.count == 3 && cleanedWords[0] == "copy" && cleanedWords[2] == "paragraph" {
            let ordinalKey = cleanedWords[1]
            if let index = Self.ordinalMap[ordinalKey] {
                return CopyParagraphCommand(rawTranscript: rawTranscript, normalizedTranscript: normalized, targetIndex: index)
            }
        }

        // Pattern 3: ["copy", "paragraph", "<ORDINAL/CARDINAL>"] or ["copy", "the", "paragraph", "<ORDINAL/CARDINAL>"]
        if cleanedWords.count == 3 && cleanedWords[0] == "copy" && cleanedWords[1] == "paragraph" {
            let ordinalKey = cleanedWords[2]
            if let index = Self.ordinalMap[ordinalKey] {
                return CopyParagraphCommand(rawTranscript: rawTranscript, normalizedTranscript: normalized, targetIndex: index)
            }
        }

        if cleanedWords.count == 4 && cleanedWords[0] == "copy" && cleanedWords[1] == "the" && cleanedWords[2] == "paragraph" {
            let ordinalKey = cleanedWords[3]
            if let index = Self.ordinalMap[ordinalKey] {
                return CopyParagraphCommand(rawTranscript: rawTranscript, normalizedTranscript: normalized, targetIndex: index)
            }
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
