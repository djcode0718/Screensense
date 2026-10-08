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
        XCTAssertTrue(result.message.contains("Multiple paragraphs visible (2)"))
        XCTAssertEqual(mockClipboard.getString(), "initial_data", "Clipboard must remain untouched on ambiguity")
    }

    func testCopyIndexedParagraphsAcrossFiveParagraphs() async throws {
        let p1 = VisibleElement(id: "p-1", type: .paragraph, text: "This is ScreenSense paragraph one.", bounds: ElementBounds(x: 50, y: 100, width: 600, height: 40), tag: "p")
        let p2 = VisibleElement(id: "p-2", type: .paragraph, text: "This is ScreenSense paragraph two.", bounds: ElementBounds(x: 50, y: 160, width: 600, height: 40), tag: "p")
        let p3 = VisibleElement(id: "p-3", type: .paragraph, text: "This is ScreenSense paragraph three.", bounds: ElementBounds(x: 50, y: 220, width: 600, height: 40), tag: "p")
        let p4 = VisibleElement(id: "p-4", type: .paragraph, text: "This is ScreenSense paragraph four.", bounds: ElementBounds(x: 50, y: 280, width: 600, height: 40), tag: "p")
        let p5 = VisibleElement(id: "p-5", type: .paragraph, text: "This is ScreenSense paragraph five.", bounds: ElementBounds(x: 50, y: 340, width: 600, height: 40), tag: "p")

        let context = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900),
            elements: [p1, p2, p3, p4, p5]
        )

        let mockClipboard = MockClipboardManager(mockString: nil)
        let mockDOMProvider = MockDOMContextProvider(context: context)
        let mockPaste = MockPasteManagerForCopy()

        let execContext = CommandExecutionContext(
            pasteManager: mockPaste,
            clipboardManager: mockClipboard,
            domContextProvider: mockDOMProvider
        )

        // 1. Copy the third paragraph
        let copyP3 = CopyParagraphCommand(rawTranscript: "copy the third paragraph", normalizedTranscript: "copy the third paragraph", targetIndex: 3)
        let resultP3 = try await copyP3.execute(context: execContext)
        XCTAssertTrue(resultP3.success)
        XCTAssertEqual(mockClipboard.getString(), "This is ScreenSense paragraph three.")
        XCTAssertTrue(resultP3.message.contains("Copied paragraph 3"))

        // 2. Copy the first paragraph
        let copyP1 = CopyParagraphCommand(rawTranscript: "copy the first paragraph", normalizedTranscript: "copy the first paragraph", targetIndex: 1)
        let resultP1 = try await copyP1.execute(context: execContext)
        XCTAssertTrue(resultP1.success)
        XCTAssertEqual(mockClipboard.getString(), "This is ScreenSense paragraph one.")

        // 3. Copy the second paragraph
        let copyP2 = CopyParagraphCommand(rawTranscript: "copy paragraph 2", normalizedTranscript: "copy paragraph 2", targetIndex: 2)
        let resultP2 = try await copyP2.execute(context: execContext)
        XCTAssertTrue(resultP2.success)
        XCTAssertEqual(mockClipboard.getString(), "This is ScreenSense paragraph two.")

        // 4. Copy the fifth paragraph
        let copyP5 = CopyParagraphCommand(rawTranscript: "copy the 5th paragraph", normalizedTranscript: "copy the 5th paragraph", targetIndex: 5)
        let resultP5 = try await copyP5.execute(context: execContext)
        XCTAssertTrue(resultP5.success)
        XCTAssertEqual(mockClipboard.getString(), "This is ScreenSense paragraph five.")
    }

    func testCopyIndexedParagraphOutOfRange() async throws {
        let p1 = VisibleElement(id: "p-1", type: .paragraph, text: "Paragraph 1", bounds: ElementBounds(x: 50, y: 100, width: 600, height: 40), tag: "p")
        let p2 = VisibleElement(id: "p-2", type: .paragraph, text: "Paragraph 2", bounds: ElementBounds(x: 50, y: 160, width: 600, height: 40), tag: "p")

        let context = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900),
            elements: [p1, p2] // only 2 paragraphs
        )

        let mockClipboard = MockClipboardManager(mockString: "unmodified")
        let mockDOMProvider = MockDOMContextProvider(context: context)
        let mockPaste = MockPasteManagerForCopy()

        let execContext = CommandExecutionContext(
            pasteManager: mockPaste,
            clipboardManager: mockClipboard,
            domContextProvider: mockDOMProvider
        )

        let command = CopyParagraphCommand(rawTranscript: "copy paragraph 4", normalizedTranscript: "copy paragraph 4", targetIndex: 4)
        let result = try await command.execute(context: execContext)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, "Only 2 visible paragraphs found.")
        XCTAssertEqual(mockClipboard.getString(), "unmodified", "Clipboard must remain unchanged")
    }

    func testCopyIndexedParagraphSpatialOrderingPreservation() async throws {
        // Scrambled input order
        let pBottom = VisibleElement(id: "p-bottom", type: .paragraph, text: "Bottom Paragraph", bounds: ElementBounds(x: 50, y: 300, width: 600, height: 40), tag: "p")
        let pTop = VisibleElement(id: "p-top", type: .paragraph, text: "Top Paragraph", bounds: ElementBounds(x: 50, y: 50, width: 600, height: 40), tag: "p")
        let pMiddle = VisibleElement(id: "p-middle", type: .paragraph, text: "Middle Paragraph", bounds: ElementBounds(x: 50, y: 150, width: 600, height: 40), tag: "p")

        let context = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900),
            elements: [pBottom, pTop, pMiddle] // Scrambled order
        )

        let mockClipboard = MockClipboardManager(mockString: nil)
        let mockDOMProvider = MockDOMContextProvider(context: context)
        let mockPaste = MockPasteManagerForCopy()

        let execContext = CommandExecutionContext(
            pasteManager: mockPaste,
            clipboardManager: mockClipboard,
            domContextProvider: mockDOMProvider
        )

        // Index 1 must be top paragraph (y: 50)
        let cmd1 = CopyParagraphCommand(rawTranscript: "copy the first paragraph", normalizedTranscript: "copy the first paragraph", targetIndex: 1)
        _ = try await cmd1.execute(context: execContext)
        XCTAssertEqual(mockClipboard.getString(), "Top Paragraph")

        // Index 2 must be middle paragraph (y: 150)
        let cmd2 = CopyParagraphCommand(rawTranscript: "copy the second paragraph", normalizedTranscript: "copy the second paragraph", targetIndex: 2)
        _ = try await cmd2.execute(context: execContext)
        XCTAssertEqual(mockClipboard.getString(), "Middle Paragraph")

        // Index 3 must be bottom paragraph (y: 300)
        let cmd3 = CopyParagraphCommand(rawTranscript: "copy the third paragraph", normalizedTranscript: "copy the third paragraph", targetIndex: 3)
        _ = try await cmd3.execute(context: execContext)
        XCTAssertEqual(mockClipboard.getString(), "Bottom Paragraph")
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
