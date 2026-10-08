import Foundation
import CoreGraphics

/// Action type requested by user
public enum ActionType: String, Codable, Equatable, Sendable {
    case copy = "copy"
    case paste = "paste"
    case explain = "explain"
    case unknown = "unknown"
}

/// Scope within which an intent operates
public enum TargetScope: Equatable, Sendable, Codable {
    case element(type: ElementType, index: Int?)
    case heading(text: String)
    case selector(String)
    case document
    case activeElement
}

/// Word-based range specification (1-based index)
public struct WordRange: Equatable, Sendable, Codable {
    public let start: Int
    public let end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

/// Substring/token-based range specification
public struct TextRange: Equatable, Sendable, Codable {
    public let startText: String
    public let endText: String

    public init(startText: String, endText: String) {
        self.startText = startText
        self.endText = endText
    }
}

/// Spatial direction / relationship relative to a reference
public enum SpatialRelationship: String, Codable, Equatable, Sendable {
    case below = "below"
    case under = "under"
    case nextTo = "next_to"
    case above = "above"
    case inside = "inside"
}

/// Spatial direction / relationship relative to mouse cursor / pointer
public enum PointerRelation: String, Codable, Equatable, Sendable {
    case under = "under"
    case above = "above"
    case below = "below"
    case nextTo = "next_to"
}

/// Scope of element targeted relative to mouse cursor / pointer
public enum PointerScope: String, Codable, Equatable, Sendable {
    case paragraph = "paragraph"
    case heading = "heading"
    case text = "text"
    case all = "all"
}

/// Scope of text selection target
public enum SelectionScope: String, Codable, Equatable, Sendable {
    case exact = "selected_text"
    case paragraph = "containing_paragraph"
    case sentence = "containing_sentence"
    case textRegion = "containing_text_region"
}

/// Generic target description for copy and context actions
public enum IntentTarget: Equatable, Sendable, Codable {
    /// Explicit element by type and optional 1-based ordinal index
    case element(type: ElementType, index: Int?)

    /// Semantic target by role (e.g. "company_name", "job_title", "email", "price", "phone_number")
    case semantic(role: String, topic: String?)

    /// Spatial relationship relative to a reference element or text
    case spatial(relationship: SpatialRelationship, referenceText: String, referenceType: ElementType?)

    /// Content targeted relative to mouse pointer / cursor position
    case pointerContext(relation: PointerRelation, scope: PointerScope?)

    /// Content targeted from active text selection
    case selection(scope: SelectionScope)

    /// Word range within an element or document (e.g. "words 5 to 12 from the third paragraph")
    case wordRange(scope: TargetScope?, range: WordRange)

    /// Text-to-text delimiter range (e.g. "from Amazon to India")
    case textRange(scope: TargetScope?, range: TextRange)
}

/// Structured intent representation for Copy operations
public struct CopyIntent: Equatable, Sendable, Codable {
    public let action: ActionType
    public let target: IntentTarget
    public let rawTranscript: String
    public let normalizedTranscript: String
    public let confidence: Double

    public init(
        target: IntentTarget,
        rawTranscript: String,
        normalizedTranscript: String,
        confidence: Double = 1.0
    ) {
        self.action = .copy
        self.target = target
        self.rawTranscript = rawTranscript
        self.normalizedTranscript = normalizedTranscript
        self.confidence = confidence
    }
}

/// Structured intent representation for Paste operations
public struct PasteIntent: Equatable, Sendable, Codable {
    public let action: ActionType
    public let rawTranscript: String
    public let normalizedTranscript: String

    public init(rawTranscript: String, normalizedTranscript: String) {
        self.action = .paste
        self.rawTranscript = rawTranscript
        self.normalizedTranscript = normalizedTranscript
    }
}

/// Unified parsed user intent
public enum StructuredUserIntent: Equatable, Sendable {
    case copy(CopyIntent)
    case paste(PasteIntent)
    case empty
    case unsupported(transcript: String, reason: String)

    public var isSuccess: Bool {
        switch self {
        case .copy, .paste: return true
        default: return false
        }
    }
}
