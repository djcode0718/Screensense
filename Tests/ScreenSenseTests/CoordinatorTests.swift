import XCTest
@testable import ScreenSenseCore

final class CoordinatorTests: XCTestCase {
    @MainActor
    private func makeSUT(
        permissionStatus: PermissionStatus = PermissionStatus(
            microphoneGranted: true,
            speechRecognitionGranted: true,
            accessibilityGranted: true
        )
    ) -> (
        coordinator: ScreenSenseCoordinator,
        mockHotkey: MockHotkeyManager,
        mockVoice: MockVoiceManager,
        mockSimulator: MockInputSimulator,
        mockPermission: MockPermissionManager
    ) {
        let mockHotkey = MockHotkeyManager()
        let mockVoice = MockVoiceManager()
        let mockSimulator = MockInputSimulator()
        let mockPaste = PasteManager(inputSimulator: mockSimulator)
        let mockClipboard = MockClipboardManager()
        let mockPermission = MockPermissionManager()
        mockPermission.status = permissionStatus
        let mockAudio = MockAudioFeedback()

        let coordinator = ScreenSenseCoordinator(
            hotkeyManager: mockHotkey,
            voiceManager: mockVoice,
            commandParser: DeterministicCommandParser(),
            pasteManager: mockPaste,
            clipboardManager: mockClipboard,
            permissionManager: mockPermission,
            audioFeedback: mockAudio
        )

        return (coordinator, mockHotkey, mockVoice, mockSimulator, mockPermission)
    }

    @MainActor
    func testCoordinatorStartAndHotkeyTrigger() async throws {
        let sut = makeSUT()
        sut.coordinator.start()
        XCTAssertTrue(sut.mockHotkey.isRegistered)

        // Trigger hotkey
        sut.mockHotkey.trigger()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(sut.mockVoice.isListening)
        XCTAssertEqual(sut.coordinator.state, .listening)
    }

    @MainActor
    func testCoordinatorVoiceToPasteExecutionFlow() async throws {
        let sut = makeSUT()
        sut.coordinator.start()
        sut.coordinator.startListening()

        XCTAssertTrue(sut.mockVoice.isListening)
        XCTAssertEqual(sut.coordinator.state, .listening)

        // Simulate speech recognition result
        sut.mockVoice.simulateFinish(result: .success("please paste"))

        // Allow MainActor async tasks to execute
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(sut.mockSimulator.simulatePasteCalled)
        if case .executed(let cmd, _) = sut.coordinator.state {
            XCTAssertTrue(cmd.contains("Paste"))
        } else {
            XCTFail("Expected .executed state, got \(sut.coordinator.state)")
        }
    }

    @MainActor
    func testCoordinatorUnsupportedCommandFlow() async throws {
        let sut = makeSUT()
        sut.coordinator.start()
        sut.coordinator.startListening()

        // Simulate unsupported command
        sut.mockVoice.simulateFinish(result: .success("open chrome"))

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(sut.mockSimulator.simulatePasteCalled)
        if case .failed(let err) = sut.coordinator.state {
            XCTAssertTrue(err.contains("Command not recognized"))
        } else {
            XCTFail("Expected .failed state, got \(sut.coordinator.state)")
        }
    }

    @MainActor
    func testCoordinatorMissingPermissionsBlocked() {
        let missing = PermissionStatus(
            microphoneGranted: false,
            speechRecognitionGranted: false,
            accessibilityGranted: false
        )
        let sut = makeSUT(permissionStatus: missing)

        sut.coordinator.start()
        sut.coordinator.handleHotkeyTriggered()

        XCTAssertFalse(sut.mockVoice.isListening)
        if case .failed(let err) = sut.coordinator.state {
            XCTAssertTrue(err.contains("Missing permissions"))
        } else {
            XCTFail("Expected missing permissions error, got \(sut.coordinator.state)")
        }
    }
}
