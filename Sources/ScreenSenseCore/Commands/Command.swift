import Foundation

/// Type of action represented by a command
public enum CommandActionType: String, Equatable, Sendable {
    case paste = "paste"
    case copy = "copy"
    case select = "select"
    case explain = "explain"
    case find = "find"
    case unknown = "unknown"
}

/// Base protocol for all executable commands
public protocol Command: Sendable {
    var actionType: CommandActionType { get }
    var rawTranscript: String { get }
    var normalizedTranscript: String { get }
    var description: String { get }

    func execute(context: CommandExecutionContext) async throws -> CommandExecutionResult
}

/// Result of parsing a transcript
public enum CommandParseResult: Equatable, Sendable {
    case success(command: AnyCommand)
    case empty
    case unsupported(transcript: String, reason: String)

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

/// Type-erased or unified Command wrapper for easy handling
public struct AnyCommand: Command, Equatable, Sendable {
    public let actionType: CommandActionType
    public let rawTranscript: String
    public let normalizedTranscript: String
    public let description: String
    private let executionClosure: @Sendable (CommandExecutionContext) async throws -> CommandExecutionResult

    public init(
        actionType: CommandActionType,
        rawTranscript: String,
        normalizedTranscript: String,
        description: String,
        executionClosure: @escaping @Sendable (CommandExecutionContext) async throws -> CommandExecutionResult
    ) {
        self.actionType = actionType
        self.rawTranscript = rawTranscript
        self.normalizedTranscript = normalizedTranscript
        self.description = description
        self.executionClosure = executionClosure
    }

    public static func == (lhs: AnyCommand, rhs: AnyCommand) -> Bool {
        lhs.actionType == rhs.actionType &&
        lhs.rawTranscript == rhs.rawTranscript &&
        lhs.normalizedTranscript == rhs.normalizedTranscript
    }

    public func execute(context: CommandExecutionContext) async throws -> CommandExecutionResult {
        try await executionClosure(context)
    }
}

/// Specific implementation of Paste Command
public struct PasteCommand: Command, Equatable, Sendable {
    public let actionType: CommandActionType = .paste
    public let rawTranscript: String
    public let normalizedTranscript: String
    public var description: String { "Paste (⌘V)" }

    public init(rawTranscript: String, normalizedTranscript: String) {
        self.rawTranscript = rawTranscript
        self.normalizedTranscript = normalizedTranscript
    }

    public func execute(context: CommandExecutionContext) async throws -> CommandExecutionResult {
        do {
            try context.pasteManager.executePaste()
            return CommandExecutionResult(
                success: true,
                message: "Pasted successfully"
            )
        } catch {
            return CommandExecutionResult(
                success: false,
                message: "Failed to paste: \(error.localizedDescription)",
                error: error
            )
        }
    }

    public func toAnyCommand() -> AnyCommand {
        AnyCommand(
            actionType: actionType,
            rawTranscript: rawTranscript,
            normalizedTranscript: normalizedTranscript,
            description: description,
            executionClosure: { [self] context in
                try await self.execute(context: context)
            }
        )
    }
}

/// Specific implementation of Copy Element Command (headings, buttons, links, paragraphs)
public struct CopyElementCommand: Command, Equatable, Sendable {
    public let actionType: CommandActionType = .copy
    public let rawTranscript: String
    public let normalizedTranscript: String
    public let targetType: ElementType // .heading, .button, .link, .paragraph
    public let targetIndex: Int? // 1-based index (e.g. 1 = first, 2 = second, nil = generic)

    public var description: String {
        let typeName = targetType.rawValue.capitalized
        if let idx = targetIndex {
            return "Copy \(typeName) #\(idx)"
        }
        return "Copy \(typeName)"
    }

    public init(
        rawTranscript: String,
        normalizedTranscript: String,
        targetType: ElementType,
        targetIndex: Int? = nil
    ) {
        self.rawTranscript = rawTranscript
        self.normalizedTranscript = normalizedTranscript
        self.targetType = targetType
        self.targetIndex = targetIndex
    }

    public func execute(context: CommandExecutionContext) async throws -> CommandExecutionResult {
        guard let domProvider = context.domContextProvider else {
            return CommandExecutionResult(
                success: false,
                message: "No browser context provider available"
            )
        }

        guard let domContext = try await domProvider.fetchCurrentDOMContext(), !domContext.elements.isEmpty else {
            return CommandExecutionResult(
                success: false,
                message: "No visible browser content available"
            )
        }

        // Preserve visual reading order
        let sorted = domContext.spatiallySortedElements

        let matchingElements: [VisibleElement]
        switch targetType {
        case .heading:
            matchingElements = sorted.filter {
                $0.type == .heading ||
                ["h1", "h2", "h3", "h4", "h5", "h6"].contains($0.tag?.lowercased())
            }
        case .button:
            matchingElements = sorted.filter {
                $0.type == .button ||
                $0.tag?.lowercased() == "button"
            }
        case .link:
            matchingElements = sorted.filter {
                $0.type == .link ||
                $0.tag?.lowercased() == "a"
            }
        case .paragraph:
            matchingElements = sorted.filter {
                $0.type == .paragraph ||
                $0.tag?.lowercased() == "p"
            }
        default:
            matchingElements = sorted.filter { $0.type == targetType }
        }

        let typeNoun = targetType.rawValue

        if matchingElements.isEmpty {
            return CommandExecutionResult(
                success: false,
                message: "No visible \(typeNoun) found"
            )
        }

        // Indexed target element selection (e.g. "copy the second button")
        if let requestedIndex = targetIndex {
            guard requestedIndex >= 1 else {
                return CommandExecutionResult(
                    success: false,
                    message: "Invalid \(typeNoun) index: \(requestedIndex)"
                )
            }

            if requestedIndex <= matchingElements.count {
                let element = matchingElements[requestedIndex - 1]
                let success = context.clipboardManager.setString(element.text)
                if success {
                    return CommandExecutionResult(
                        success: true,
                        message: "Copied \(typeNoun) \(requestedIndex) to clipboard: \"\(element.text.prefix(40))...\""
                    )
                } else {
                    return CommandExecutionResult(
                        success: false,
                        message: "Failed to set clipboard content"
                    )
                }
            } else {
                let plural = matchingElements.count == 1 ? "" : "s"
                return CommandExecutionResult(
                    success: false,
                    message: "Only \(matchingElements.count) visible \(typeNoun)\(plural) found."
                )
            }
        }

        // Generic single-element resolution (e.g. "copy the button")
        if matchingElements.count == 1 {
            let element = matchingElements[0]
            let success = context.clipboardManager.setString(element.text)
            if success {
                return CommandExecutionResult(
                    success: true,
                    message: "Copied \(typeNoun) to clipboard: \"\(element.text.prefix(40))...\""
                )
            } else {
                return CommandExecutionResult(
                    success: false,
                    message: "Failed to set clipboard content"
                )
            }
        }

        let pluralNoun = typeNoun.hasSuffix("s") ? typeNoun : "\(typeNoun)s"
        return CommandExecutionResult(
            success: false,
            message: "Multiple \(pluralNoun) visible (\(matchingElements.count)). Please specify which \(typeNoun) (e.g. 'copy the first \(typeNoun)')."
        )
    }

    public func toAnyCommand() -> AnyCommand {
        AnyCommand(
            actionType: actionType,
            rawTranscript: rawTranscript,
            normalizedTranscript: normalizedTranscript,
            description: description,
            executionClosure: { [self] context in
                try await self.execute(context: context)
            }
        )
    }
}

/// Backward compatibility alias / helper for CopyParagraphCommand
public struct CopyParagraphCommand: Command, Equatable, Sendable {
    private let underlying: CopyElementCommand

    public var actionType: CommandActionType { underlying.actionType }
    public var rawTranscript: String { underlying.rawTranscript }
    public var normalizedTranscript: String { underlying.normalizedTranscript }
    public var targetIndex: Int? { underlying.targetIndex }
    public var description: String { underlying.description }

    public init(rawTranscript: String, normalizedTranscript: String, targetIndex: Int? = nil) {
        self.underlying = CopyElementCommand(
            rawTranscript: rawTranscript,
            normalizedTranscript: normalizedTranscript,
            targetType: .paragraph,
            targetIndex: targetIndex
        )
    }

    public func execute(context: CommandExecutionContext) async throws -> CommandExecutionResult {
        try await underlying.execute(context: context)
    }

    public func toAnyCommand() -> AnyCommand {
        underlying.toAnyCommand()
    }
}

/// Execution context passed to commands
public struct CommandExecutionContext: Sendable {
    public let pasteManager: PasteManagerProtocol
    public let clipboardManager: ClipboardManagerProtocol
    public let domContextProvider: DOMContextProviderProtocol?

    public init(
        pasteManager: PasteManagerProtocol,
        clipboardManager: ClipboardManagerProtocol,
        domContextProvider: DOMContextProviderProtocol? = nil
    ) {
        self.pasteManager = pasteManager
        self.clipboardManager = clipboardManager
        self.domContextProvider = domContextProvider
    }
}

/// Result of executing a command
public struct CommandExecutionResult: Equatable, Sendable {
    public let success: Bool
    public let message: String
    public let errorDescription: String?

    public init(success: Bool, message: String, error: Error? = nil) {
        self.success = success
        self.message = message
        self.errorDescription = error?.localizedDescription
    }

    public static func == (lhs: CommandExecutionResult, rhs: CommandExecutionResult) -> Bool {
        lhs.success == rhs.success &&
        lhs.message == rhs.message &&
        lhs.errorDescription == rhs.errorDescription
    }
}
