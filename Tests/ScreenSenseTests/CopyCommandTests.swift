import XCTest
@testable import ScreenSenseCore

// MARK: - Mock Implementations for CopyCommand Testing

final class MockDOMContextProvider: DOMContextProviderProtocol, @unchecked Sendable {
    var stubbedContext: VisibleContext?

    init(context: VisibleContext? = nil) {
        self.stubbedContext = context
    }

    func fetchCurrentDOMContext() async throws -> VisibleContext? {
        return stubbedContext
    }
}

final class MockPasteManagerForCopy: PasteManagerProtocol, @unchecked Sendable {
    func executePaste() throws {}
}

// MARK: - CopyCommand Tests

final class CopyCommandTests: XCTestCase {

    func testCopySingleVisibleParagraphSuccess() async throws {
        let paragraphText = "ScreenSense is a macOS-native voice-controlled screen interaction assistant."
        let element = VisibleElement(
            id: "p-1",
            type: .paragraph,
            text: paragraphText,
            bounds: ElementBounds(x: 100, y: 100, width: 600, height: 80),
            tag: "p"
        )
        let heading = VisibleElement(
            id: "h-1",
            type: .heading,
            text: "ScreenSense Overview",
            bounds: ElementBounds(x: 100, y: 50, width: 400, height: 40),
            tag: "h1"
        )

        let context = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900),
            elements: [heading, element] // 1 heading, 1 paragraph
        )

        let mockClipboard = MockClipboardManager(mockString: nil)
        let mockDOMProvider = MockDOMContextProvider(context: context)
        let mockPaste = MockPasteManagerForCopy()

        let execContext = CommandExecutionContext(
            pasteManager: mockPaste,
            clipboardManager: mockClipboard,
            domContextProvider: mockDOMProvider
        )

        let command = CopyParagraphCommand(rawTranscript: "copy the paragraph", normalizedTranscript: "copy the paragraph")
        let result = try await command.execute(context: execContext)

        XCTAssertTrue(result.success)
        XCTAssertEqual(mockClipboard.getString(), paragraphText)
        XCTAssertTrue(result.message.contains("Copied paragraph"))
    }

    func testCopyParagraphFailsWhenNoParagraphExists() async throws {
        let heading = VisibleElement(
            id: "h-1",
            type: .heading,
            text: "Only a heading here",
            bounds: ElementBounds(x: 100, y: 50, width: 400, height: 40),
            tag: "h1"
        )
        let button = VisibleElement(
            id: "btn-1",
            type: .button,
            text: "Submit",
            bounds: ElementBounds(x: 100, y: 120, width: 100, height: 30),
            tag: "button"
        )

        let context = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900),
            elements: [heading, button] // 0 paragraphs
        )

        let mockClipboard = MockClipboardManager(mockString: "previous_clipboard_data")
        let mockDOMProvider = MockDOMContextProvider(context: context)
        let mockPaste = MockPasteManagerForCopy()

        let execContext = CommandExecutionContext(
            pasteManager: mockPaste,
            clipboardManager: mockClipboard,
            domContextProvider: mockDOMProvider
        )

        let command = CopyParagraphCommand(rawTranscript: "copy the paragraph", normalizedTranscript: "copy the paragraph")
        let result = try await command.execute(context: execContext)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, "No visible paragraph found")
        XCTAssertEqual(mockClipboard.getString(), "previous_clipboard_data", "Clipboard must remain untouched")
    }

    func testCopyParagraphDisambiguationWhenMultipleParagraphsExist() async throws {
        let p1 = VisibleElement(
            id: "p-1",
            type: .paragraph,
            text: "First visible paragraph text.",
            bounds: ElementBounds(x: 100, y: 100, width: 600, height: 50),
            tag: "p"
        )
        let p2 = VisibleElement(
            id: "p-2",
            type: .paragraph,
            text: "Second visible paragraph text.",
            bounds: ElementBounds(x: 100, y: 160, width: 600, height: 50),
            tag: "p"
        )

        let context = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900),
            elements: [p1, p2] // 2 paragraphs
        )

        let mockClipboard = MockClipboardManager(mockString: "initial_data")
        let mockDOMProvider = MockDOMContextProvider(context: context)
        let mockPaste = MockPasteManagerForCopy()

        let execContext = CommandExecutionContext(
            pasteManager: mockPaste,
            clipboardManager: mockClipboard,
            domContextProvider: mockDOMProvider
        )

        let command = CopyParagraphCommand(rawTranscript: "copy the paragraph", normalizedTranscript: "copy the paragraph")
        let result = try await command.execute(context: execContext)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, "Multiple paragraphs visible (2). Please specify which paragraph.")
        XCTAssertEqual(mockClipboard.getString(), "initial_data", "Clipboard must remain untouched on ambiguity")
    }

    func testCopyParagraphWhenNoDOMContextAvailable() async throws {
        let mockClipboard = MockClipboardManager(mockString: nil)
        let mockDOMProvider = MockDOMContextProvider(context: nil)
        let mockPaste = MockPasteManagerForCopy()

        let execContext = CommandExecutionContext(
            pasteManager: mockPaste,
            clipboardManager: mockClipboard,
            domContextProvider: mockDOMProvider
        )

        let command = CopyParagraphCommand(rawTranscript: "copy the paragraph", normalizedTranscript: "copy the paragraph")
        let result = try await command.execute(context: execContext)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, "No visible browser content available")
    }
}
