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
        if isCopyParagraphCommand(normalized) {
            let copyCmd = CopyParagraphCommand(rawTranscript: transcript, normalizedTranscript: normalized)
            return .success(command: copyCmd.toAnyCommand())
        }

        return .unsupported(
            transcript: transcript,
            reason: "Command not recognized: \"\(transcript)\""
        )
    }

    private func isCopyParagraphCommand(_ normalized: String) -> Bool {
        let directMatches: Set<String> = [
            "copy the paragraph",
            "copy paragraph",
            "copy this paragraph",
            "copy that paragraph",
            "please copy the paragraph",
            "please copy paragraph",
            "can you copy the paragraph",
            "copy the paragraph please",
            "copy paragraph please"
        ]

        if directMatches.contains(normalized) {
            return true
        }

        let words = normalized.components(separatedBy: " ").filter { !$0.isEmpty }
        let fillerWords: Set<String> = ["please", "hey", "can", "you", "just", "screensense", "now", "would", "could", "will"]
        let cleanedWords = words.filter { !fillerWords.contains($0) }
        let cleanedPhrase = cleanedWords.joined(separator: " ")

        if directMatches.contains(cleanedPhrase) {
            return true
        }

        if cleanedWords == ["copy", "the", "paragraph"] ||
           cleanedWords == ["copy", "paragraph"] ||
           cleanedWords == ["copy", "this", "paragraph"] ||
           cleanedWords == ["copy", "that", "paragraph"] {
            return true
        }

        return false
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
