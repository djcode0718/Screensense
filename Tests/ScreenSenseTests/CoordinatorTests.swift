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
        mockPermission: MockPermissionManager,
        mockClipboard: MockClipboardManager,
        bridge: LocalBrowserBridge
    ) {
        let mockHotkey = MockHotkeyManager()
        let mockVoice = MockVoiceManager()
        let mockSimulator = MockInputSimulator()
        let mockPaste = PasteManager(inputSimulator: mockSimulator)
        let mockClipboard = MockClipboardManager(mockString: nil)
        let mockPermission = MockPermissionManager()
        mockPermission.status = permissionStatus
        let mockAudio = MockAudioFeedback()
        let bridge = LocalBrowserBridge(port: 41929)

        let coordinator = ScreenSenseCoordinator(
            hotkeyManager: mockHotkey,
            voiceManager: mockVoice,
            commandParser: DeterministicCommandParser(),
            pasteManager: mockPaste,
            clipboardManager: mockClipboard,
            permissionManager: mockPermission,
            audioFeedback: mockAudio,
            browserBridge: bridge
        )

        return (coordinator, mockHotkey, mockVoice, mockSimulator, mockPermission, mockClipboard, bridge)
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

    @MainActor
    func testCoordinatorVoiceToCopyExecutionFlow() async throws {
        let sut = makeSUT()
        sut.coordinator.start()

        // Populate DOM context with 1 paragraph
        let text = "Copied text from voice coordinator flow"
        let p = VisibleElement(
            id: "p-test",
            type: .paragraph,
            text: text,
            bounds: ElementBounds(x: 10, y: 10, width: 200, height: 40),
            tag: "p"
        )
        let ctx = VisibleContext(source: .dom, viewport: ViewportInfo(width: 800, height: 600), elements: [p])
        sut.bridge.updateContext(ctx)

        sut.coordinator.startListening()
        XCTAssertTrue(sut.mockVoice.isListening)

        // Simulate voice recognition of "copy the paragraph"
        sut.mockVoice.simulateFinish(result: .success("copy the paragraph"))

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(sut.mockClipboard.getString(), text)
        if case .executed(let cmd, _) = sut.coordinator.state {
            XCTAssertTrue(cmd.contains("Copy"))
        } else {
            XCTFail("Expected .executed state, got \(sut.coordinator.state)")
        }
    }
}
