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

    @MainActor
    func testCoordinatorVoiceToCopyThirdParagraphExecutionFlow() async throws {
        let sut = makeSUT()
        sut.coordinator.start()

        // 5 visible paragraphs
        let p1 = VisibleElement(id: "p-1", type: .paragraph, text: "This is ScreenSense paragraph one.", bounds: ElementBounds(x: 50, y: 100, width: 600, height: 40), tag: "p")
        let p2 = VisibleElement(id: "p-2", type: .paragraph, text: "This is ScreenSense paragraph two.", bounds: ElementBounds(x: 50, y: 160, width: 600, height: 40), tag: "p")
        let p3 = VisibleElement(id: "p-3", type: .paragraph, text: "This is ScreenSense paragraph three.", bounds: ElementBounds(x: 50, y: 220, width: 600, height: 40), tag: "p")
        let p4 = VisibleElement(id: "p-4", type: .paragraph, text: "This is ScreenSense paragraph four.", bounds: ElementBounds(x: 50, y: 280, width: 600, height: 40), tag: "p")
        let p5 = VisibleElement(id: "p-5", type: .paragraph, text: "This is ScreenSense paragraph five.", bounds: ElementBounds(x: 50, y: 340, width: 600, height: 40), tag: "p")

        let ctx = VisibleContext(source: .dom, viewport: ViewportInfo(width: 1440, height: 900), elements: [p1, p2, p3, p4, p5])
        sut.bridge.updateContext(ctx)

        sut.coordinator.startListening()
        XCTAssertTrue(sut.mockVoice.isListening)

        // Voice says "copy the third paragraph"
        sut.mockVoice.simulateFinish(result: .success("copy the third paragraph"))

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(sut.mockClipboard.getString(), "This is ScreenSense paragraph three.")
        if case .executed(let cmd, let msg) = sut.coordinator.state {
            XCTAssertTrue(cmd.contains("Copy Paragraph #3"))
            XCTAssertTrue(msg.contains("Copied paragraph 3"))
        } else {
            XCTFail("Expected .executed state, got \(sut.coordinator.state)")
        }
    }

    @MainActor
    func testCoordinatorVoiceToCopyHeadingButtonLinkExecutionFlow() async throws {
        let sut = makeSUT()
        sut.coordinator.start()

        let h1 = VisibleElement(id: "h-1", type: .heading, text: "Heading One", bounds: ElementBounds(x: 50, y: 50, width: 400, height: 40), tag: "h1")
        let h2 = VisibleElement(id: "h-2", type: .heading, text: "Heading Two", bounds: ElementBounds(x: 50, y: 150, width: 400, height: 40), tag: "h2")
        let b1 = VisibleElement(id: "b-1", type: .button, text: "Button One", bounds: ElementBounds(x: 50, y: 250, width: 120, height: 40), tag: "button")
        let b2 = VisibleElement(id: "b-2", type: .button, text: "Button Two", bounds: ElementBounds(x: 180, y: 250, width: 120, height: 40), tag: "button")
        let l1 = VisibleElement(id: "l-1", type: .link, text: "Link One", bounds: ElementBounds(x: 50, y: 350, width: 100, height: 30), tag: "a")
        let l2 = VisibleElement(id: "l-2", type: .link, text: "Link Two", bounds: ElementBounds(x: 160, y: 350, width: 100, height: 30), tag: "a")
        let l3 = VisibleElement(id: "l-3", type: .link, text: "Link Three", bounds: ElementBounds(x: 270, y: 350, width: 100, height: 30), tag: "a")

        let ctx = VisibleContext(source: .dom, viewport: ViewportInfo(width: 1440, height: 900), elements: [h1, h2, b1, b2, l1, l2, l3])
        sut.bridge.updateContext(ctx)

        let testCommands: [(voice: String, expectedText: String, expectedCmd: String)] = [
            ("Copy the first heading", "Heading One", "Copy Heading #1"),
            ("Copy heading 2", "Heading Two", "Copy Heading #2"),
            ("Copy the first button", "Button One", "Copy Button #1"),
            ("Copy button 2", "Button Two", "Copy Button #2"),
            ("Copy the third link", "Link Three", "Copy Link #3"),
            ("Copy link 3", "Link Three", "Copy Link #3")
        ]

        for test in testCommands {
            sut.coordinator.startListening()
            sut.mockVoice.simulateFinish(result: .success(test.voice))
            try await Task.sleep(nanoseconds: 80_000_000)

            XCTAssertEqual(sut.mockClipboard.getString(), test.expectedText, "Mismatch for voice input '\(test.voice)'")
            if case .executed(let cmd, _) = sut.coordinator.state {
                XCTAssertTrue(cmd.contains(test.expectedCmd), "Expected command containing '\(test.expectedCmd)' for '\(test.voice)', got '\(cmd)'")
            } else {
                XCTFail("Expected .executed state for '\(test.voice)', got \(sut.coordinator.state)")
            }
        }
    }

    @MainActor
    func testCoordinatorVoiceToSemanticCopyExecutionFlow() async throws {
        let sut = makeSUT()
        sut.coordinator.start()

        let title = VisibleElement(id: "h1", type: .heading, text: "ScreenSense Test Store", bounds: ElementBounds(x: 50, y: 50, width: 400, height: 40), tag: "h1")
        let introP = VisibleElement(id: "p1", type: .paragraph, text: "Product: Premium Wireless Headphones.", bounds: ElementBounds(x: 50, y: 100, width: 600, height: 30), tag: "p")
        let priceDiv = VisibleElement(id: "div-price", type: .genericText, text: "Price: ₹2,499", bounds: ElementBounds(x: 50, y: 150, width: 200, height: 30), tag: "div")
        let emailDiv = VisibleElement(id: "div-email", type: .genericText, text: "Support: support@screensense.test", bounds: ElementBounds(x: 50, y: 190, width: 300, height: 30), tag: "div")
        let button = VisibleElement(id: "btn-apply", type: .button, text: "Apply Coupon", bounds: ElementBounds(x: 50, y: 240, width: 140, height: 40), tag: "button")
        let adjacentText = VisibleElement(id: "span-note", type: .genericText, text: "Discount available for students.", bounds: ElementBounds(x: 200, y: 245, width: 250, height: 30), tag: "span")
        let h2 = VisibleElement(id: "h2", type: .heading, text: "Heading Two", bounds: ElementBounds(x: 50, y: 320, width: 400, height: 40), tag: "h2")
        let h2Text = VisibleElement(id: "p-h2", type: .paragraph, text: "This is ScreenSense paragraph under Heading Two.", bounds: ElementBounds(x: 50, y: 370, width: 600, height: 30), tag: "p")

        let ctx = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900),
            elements: [title, introP, priceDiv, emailDiv, button, adjacentText, h2, h2Text]
        )
        sut.bridge.updateContext(ctx)

        let semanticTests: [(voice: String, expectedCopied: String)] = [
            ("Copy the email address", "support@screensense.test"),
            ("Copy the price", "₹2,499"),
            ("Copy the text below the title", "Product: Premium Wireless Headphones."),
            ("Copy the text next to the Apply button", "Discount available for students."),
            ("Copy the text under Heading Two", "This is ScreenSense paragraph under Heading Two.")
        ]

        for test in semanticTests {
            sut.coordinator.startListening()
            sut.mockVoice.simulateFinish(result: .success(test.voice))
            try await Task.sleep(nanoseconds: 80_000_000)

            XCTAssertEqual(sut.mockClipboard.getString(), test.expectedCopied, "Failed to copy expected text for '\(test.voice)'")
            if case .executed(let cmd, let msg) = sut.coordinator.state {
                XCTAssertTrue(cmd.contains("Copy"), "Expected Copy command description for '\(test.voice)'")
                XCTAssertTrue(msg.contains("Copied"), "Expected execution success message for '\(test.voice)'")
            } else {
                XCTFail("Expected .executed state for '\(test.voice)', got \(sut.coordinator.state)")
            }
        }
    }
}
