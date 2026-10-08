import Foundation

/// Protocol for global keyboard hotkey management
public protocol HotkeyManagerProtocol: AnyObject, Sendable {
    /// Registers a global hotkey with a trigger handler
    func register(handler: @escaping @Sendable () -> Void) throws
    /// Unregisters the active hotkey
    func unregister()
    /// Is the hotkey currently active
    var isRegistered: Bool { get }
}

/// Protocol for speech recognition engines (Apple Speech, Whisper, etc.)
public protocol SpeechRecognizerProtocol: AnyObject, Sendable {
    /// Starts recognition and streams partial/final transcripts
    func startRecognition(
        onPartialResult: @escaping @Sendable (String) -> Void,
        onFinalResult: @escaping @Sendable (Result<String, Error>) -> Void
    ) throws

    /// Stops audio capture and finalizes recognition
    func stopRecognition()

    /// Is recognizer currently running
    var isRecording: Bool { get }
}

/// Protocol for coordinating voice input lifecycle
public protocol VoiceManagerProtocol: AnyObject, Sendable {
    func startListening(
        onPartialTranscript: @escaping @Sendable (String) -> Void,
        onCompletion: @escaping @Sendable (Result<String, Error>) -> Void
    ) throws

    func stopListening()

    var isListening: Bool { get }
}

/// Protocol for parsing speech transcripts into structured commands
public protocol CommandParserProtocol: Sendable {
    func parse(transcript: String) -> CommandParseResult
}

/// Protocol for reading/writing clipboard (kept separate from pasting)
public protocol ClipboardManagerProtocol: Sendable {
    func hasContent() -> Bool
    func getString() -> String?
}

/// Protocol for low-level input simulation (e.g. CGEvent synthesis)
public protocol InputSimulatorProtocol: Sendable {
    func simulatePasteShortcut() throws
}

/// Protocol for executing paste operations
public protocol PasteManagerProtocol: Sendable {
    func executePaste() throws
}

/// Protocol for managing and checking macOS permissions
public protocol PermissionManagerProtocol: AnyObject, Sendable {
    func checkAllPermissions() -> PermissionStatus
    func requestMicrophonePermission() async -> Bool
    func requestSpeechRecognitionPermission() async -> Bool
    func requestAccessibilityPermission() -> Bool
    func openSystemSettings(for permission: SystemSettingsTarget)
}

public enum SystemSettingsTarget: Sendable {
    case accessibility
    case microphone
    case speechRecognition
}
