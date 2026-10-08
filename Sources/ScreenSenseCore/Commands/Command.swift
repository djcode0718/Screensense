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

/// Specific implementation of Copy Paragraph Command
public struct CopyParagraphCommand: Command, Equatable, Sendable {
    public let actionType: CommandActionType = .copy
    public let rawTranscript: String
    public let normalizedTranscript: String
    public var description: String { "Copy Paragraph" }

    public init(rawTranscript: String, normalizedTranscript: String) {
        self.rawTranscript = rawTranscript
        self.normalizedTranscript = normalizedTranscript
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

        let paragraphs = domContext.elements.filter { $0.type == .paragraph || $0.tag?.lowercased() == "p" }

        if paragraphs.isEmpty {
            return CommandExecutionResult(
                success: false,
                message: "No visible paragraph found"
            )
        }

        if paragraphs.count == 1 {
            let paragraph = paragraphs[0]
            let success = context.clipboardManager.setString(paragraph.text)
            if success {
                return CommandExecutionResult(
                    success: true,
                    message: "Copied paragraph to clipboard: \"\(paragraph.text.prefix(40))...\""
                )
            } else {
                return CommandExecutionResult(
                    success: false,
                    message: "Failed to set clipboard content"
                )
            }
        }

        return CommandExecutionResult(
            success: false,
            message: "Multiple paragraphs visible (\(paragraphs.count)). Please specify which paragraph."
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
