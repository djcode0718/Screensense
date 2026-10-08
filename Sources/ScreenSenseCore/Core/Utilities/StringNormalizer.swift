import Foundation

public enum StringNormalizer {
    /// Normalizes spoken text by:
    /// - Lowercasing
    /// - Removing common punctuation (periods, commas, exclamation marks, question marks, quotes)
    /// - Trimming and collapsing consecutive whitespaces
    public static func normalize(_ text: String) -> String {
        var result = text.lowercased()

        // Replace common punctuation with space or remove
        let punctuationToStrip = CharacterSet(charactersIn: ".,!?:;\"'“”‘’`~-—–_()[]{}<>\\/|@#$%^&*")
        result = result.components(separatedBy: punctuationToStrip).joined(separator: " ")

        // Collapse whitespace
        let components = result.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        return components.joined(separator: " ")
    }
}
