import XCTest
@testable import ScreenSenseCore

final class MockInputSimulator: InputSimulatorProtocol, @unchecked Sendable {
    var simulatePasteCalled = false
    var shouldThrowError: Error?

    func simulatePasteShortcut() throws {
        simulatePasteCalled = true
        if let error = shouldThrowError {
            throw error
        }
    }
}

final class MockClipboardManager: ClipboardManagerProtocol, @unchecked Sendable {
    var mockString: String? = "Test Clipboard Content"

    func hasContent() -> Bool {
        return mockString != nil
    }

    func getString() -> String? {
        return mockString
    }
}

final class MockHotkeyManager: HotkeyManagerProtocol, @unchecked Sendable {
    var isRegistered: Bool = false
    var registeredHandler: (@Sendable () -> Void)?

    func register(handler: @escaping @Sendable () -> Void) throws {
        isRegistered = true
        registeredHandler = handler
    }

    func unregister() {
        isRegistered = false
        registeredHandler = nil
    }

    func trigger() {
        registeredHandler?()
    }
}

final class MockVoiceManager: VoiceManagerProtocol, @unchecked Sendable {
    var isListening: Bool = false
    var partialHandler: (@Sendable (String) -> Void)?
    var completionHandler: (@Sendable (Result<String, Error>) -> Void)?

    func startListening(
        onPartialTranscript: @escaping @Sendable (String) -> Void,
        onCompletion: @escaping @Sendable (Result<String, Error>) -> Void
    ) throws {
        isListening = true
        partialHandler = onPartialTranscript
        completionHandler = onCompletion
    }

    func stopListening() {
        isListening = false
    }

    func simulateSpeech(partial: String) {
        partialHandler?(partial)
    }

    func simulateFinish(result: Result<String, Error>) {
        isListening = false
        completionHandler?(result)
    }
}

final class MockPermissionManager: PermissionManagerProtocol, @unchecked Sendable {
    var status = PermissionStatus(microphoneGranted: true, speechRecognitionGranted: true, accessibilityGranted: true)

    func checkAllPermissions() -> PermissionStatus {
        return status
    }

    func requestMicrophonePermission() async -> Bool {
        return status.microphoneGranted
    }

    func requestSpeechRecognitionPermission() async -> Bool {
        return status.speechRecognitionGranted
    }

    func requestAccessibilityPermission() -> Bool {
        return status.accessibilityGranted
    }

    func requestScreenRecordingPermission() -> Bool {
        return status.screenRecordingGranted
    }

    func openSystemSettings(for permission: SystemSettingsTarget) {}
}

final class MockAudioFeedback: AudioFeedbackProtocol, @unchecked Sendable {
    var playedSounds: [FeedbackSoundType] = []

    func playSound(_ type: FeedbackSoundType) {
        playedSounds.append(type)
    }
}

final class PasteManagerTests: XCTestCase {
    func testPasteManagerSuccess() throws {
        let mockSimulator = MockInputSimulator()
        let pasteManager = PasteManager(inputSimulator: mockSimulator)

        try pasteManager.executePaste()

        XCTAssertTrue(mockSimulator.simulatePasteCalled)
    }

    func testPasteManagerErrorPropagation() {
        let mockSimulator = MockInputSimulator()
        mockSimulator.shouldThrowError = InputSimulationError.accessibilityPermissionRequired
        let pasteManager = PasteManager(inputSimulator: mockSimulator)

        XCTAssertThrowsError(try pasteManager.executePaste()) { error in
            guard let simError = error as? InputSimulationError,
                  case .accessibilityPermissionRequired = simError else {
                XCTFail("Expected accessibilityPermissionRequired error, got \(error)")
                return
            }
        }
    }

    func testPasteCommandExecutionThroughContext() async throws {
        let mockSimulator = MockInputSimulator()
        let pasteManager = PasteManager(inputSimulator: mockSimulator)
        let clipboardManager = MockClipboardManager()

        let context = CommandExecutionContext(
            pasteManager: pasteManager,
            clipboardManager: clipboardManager
        )

        let pasteCommand = PasteCommand(rawTranscript: "paste", normalizedTranscript: "paste")
        let result = try await pasteCommand.execute(context: context)

        XCTAssertTrue(result.success)
        XCTAssertTrue(mockSimulator.simulatePasteCalled)
    }
}
