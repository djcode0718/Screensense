import Foundation

/// Represents the high-level state of ScreenSense
public enum ScreenSenseState: Equatable, Sendable {
    case idle
    case listening
    case processing(transcript: String)
    case executed(command: String, message: String)
    case failed(error: String)

    public var statusDescription: String {
        switch self {
        case .idle:
            return "Ready"
        case .listening:
            return "Listening..."
        case .processing(let transcript):
            return "Processing: \"\(transcript)\""
        case .executed(let command, _):
            return "Executed: \(command)"
        case .failed(let error):
            return "Error: \(error)"
        }
    }

    public var isListening: Bool {
        if case .listening = self { return true }
        return false
    }
}

/// Permission statuses for required capabilities
public struct PermissionStatus: Equatable, Sendable {
    public let microphoneGranted: Bool
    public let speechRecognitionGranted: Bool
    public let accessibilityGranted: Bool
    public let screenRecordingGranted: Bool

    public init(
        microphoneGranted: Bool = false,
        speechRecognitionGranted: Bool = false,
        accessibilityGranted: Bool = false,
        screenRecordingGranted: Bool = false
    ) {
        self.microphoneGranted = microphoneGranted
        self.speechRecognitionGranted = speechRecognitionGranted
        self.accessibilityGranted = accessibilityGranted
        self.screenRecordingGranted = screenRecordingGranted
    }

    public var allGranted: Bool {
        microphoneGranted && speechRecognitionGranted && accessibilityGranted && screenRecordingGranted
    }

    public var missingPermissions: [String] {
        var missing: [String] = []
        if !microphoneGranted { missing.append("Microphone") }
        if !speechRecognitionGranted { missing.append("Speech Recognition") }
        if !accessibilityGranted { missing.append("Accessibility") }
        if !screenRecordingGranted { missing.append("Screen Recording") }
        return missing
    }
}
