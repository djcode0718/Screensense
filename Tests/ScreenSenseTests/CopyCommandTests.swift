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

    // MARK: - Paragraph Tests

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

        let command = CopyElementCommand(rawTranscript: "copy the paragraph", normalizedTranscript: "copy the paragraph", targetType: .paragraph)
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

        let command = CopyElementCommand(rawTranscript: "copy the paragraph", normalizedTranscript: "copy the paragraph", targetType: .paragraph)
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

        let command = CopyElementCommand(rawTranscript: "copy the paragraph", normalizedTranscript: "copy the paragraph", targetType: .paragraph)
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
        let copyP3 = CopyElementCommand(rawTranscript: "copy the third paragraph", normalizedTranscript: "copy the third paragraph", targetType: .paragraph, targetIndex: 3)
        let resultP3 = try await copyP3.execute(context: execContext)
        XCTAssertTrue(resultP3.success)
        XCTAssertEqual(mockClipboard.getString(), "This is ScreenSense paragraph three.")
        XCTAssertTrue(resultP3.message.contains("Copied paragraph 3"))

        // 2. Copy the first paragraph
        let copyP1 = CopyElementCommand(rawTranscript: "copy the first paragraph", normalizedTranscript: "copy the first paragraph", targetType: .paragraph, targetIndex: 1)
        let resultP1 = try await copyP1.execute(context: execContext)
        XCTAssertTrue(resultP1.success)
        XCTAssertEqual(mockClipboard.getString(), "This is ScreenSense paragraph one.")

        // 3. Copy the second paragraph
        let copyP2 = CopyElementCommand(rawTranscript: "copy paragraph 2", normalizedTranscript: "copy paragraph 2", targetType: .paragraph, targetIndex: 2)
        let resultP2 = try await copyP2.execute(context: execContext)
        XCTAssertTrue(resultP2.success)
        XCTAssertEqual(mockClipboard.getString(), "This is ScreenSense paragraph two.")

        // 4. Copy the fifth paragraph
        let copyP5 = CopyElementCommand(rawTranscript: "copy the 5th paragraph", normalizedTranscript: "copy the 5th paragraph", targetType: .paragraph, targetIndex: 5)
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

        let command = CopyElementCommand(rawTranscript: "copy paragraph 4", normalizedTranscript: "copy paragraph 4", targetType: .paragraph, targetIndex: 4)
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
        let cmd1 = CopyElementCommand(rawTranscript: "copy the first paragraph", normalizedTranscript: "copy the first paragraph", targetType: .paragraph, targetIndex: 1)
        _ = try await cmd1.execute(context: execContext)
        XCTAssertEqual(mockClipboard.getString(), "Top Paragraph")

        // Index 2 must be middle paragraph (y: 150)
        let cmd2 = CopyElementCommand(rawTranscript: "copy the second paragraph", normalizedTranscript: "copy the second paragraph", targetType: .paragraph, targetIndex: 2)
        _ = try await cmd2.execute(context: execContext)
        XCTAssertEqual(mockClipboard.getString(), "Middle Paragraph")

        // Index 3 must be bottom paragraph (y: 300)
        let cmd3 = CopyElementCommand(rawTranscript: "copy the third paragraph", normalizedTranscript: "copy the third paragraph", targetType: .paragraph, targetIndex: 3)
        _ = try await cmd3.execute(context: execContext)
        XCTAssertEqual(mockClipboard.getString(), "Bottom Paragraph")
    }

    // MARK: - Heading Tests

    func testCopySingleHeadingSuccess() async throws {
        let heading = VisibleElement(
            id: "h-1",
            type: .heading,
            text: "Heading One",
            bounds: ElementBounds(x: 50, y: 50, width: 400, height: 40),
            tag: "h1"
        )
        let context = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900),
            elements: [heading]
        )

        let mockClipboard = MockClipboardManager(mockString: nil)
        let mockDOMProvider = MockDOMContextProvider(context: context)
        let mockPaste = MockPasteManagerForCopy()

        let execContext = CommandExecutionContext(
            pasteManager: mockPaste,
            clipboardManager: mockClipboard,
            domContextProvider: mockDOMProvider
        )

        let command = CopyElementCommand(rawTranscript: "copy the heading", normalizedTranscript: "copy the heading", targetType: .heading)
        let result = try await command.execute(context: execContext)

        XCTAssertTrue(result.success)
        XCTAssertEqual(mockClipboard.getString(), "Heading One")
        XCTAssertTrue(result.message.contains("Copied heading"))
    }

    func testCopyHeadingAmbiguityWhenMultipleHeadingsExist() async throws {
        let h1 = VisibleElement(id: "h-1", type: .heading, text: "Heading One", bounds: ElementBounds(x: 50, y: 50, width: 400, height: 40), tag: "h1")
        let h2 = VisibleElement(id: "h-2", type: .heading, text: "Heading Two", bounds: ElementBounds(x: 50, y: 300, width: 400, height: 40), tag: "h2")

        let context = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900),
            elements: [h1, h2]
        )

        let mockClipboard = MockClipboardManager(mockString: "unmodified")
        let mockDOMProvider = MockDOMContextProvider(context: context)
        let mockPaste = MockPasteManagerForCopy()

        let execContext = CommandExecutionContext(
            pasteManager: mockPaste,
            clipboardManager: mockClipboard,
            domContextProvider: mockDOMProvider
        )

        let command = CopyElementCommand(rawTranscript: "copy the heading", normalizedTranscript: "copy the heading", targetType: .heading)
        let result = try await command.execute(context: execContext)

        XCTAssertFalse(result.success)
        XCTAssertTrue(result.message.contains("Multiple headings visible (2)"))
        XCTAssertEqual(mockClipboard.getString(), "unmodified")
    }

    func testCopyIndexedHeadings() async throws {
        let h1 = VisibleElement(id: "h-1", type: .heading, text: "Heading One", bounds: ElementBounds(x: 50, y: 50, width: 400, height: 40), tag: "h1")
        let h2 = VisibleElement(id: "h-2", type: .heading, text: "Heading Two", bounds: ElementBounds(x: 50, y: 300, width: 400, height: 40), tag: "h2")

        let context = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900),
            elements: [h2, h1] // Scrambled order
        )

        let mockClipboard = MockClipboardManager(mockString: nil)
        let mockDOMProvider = MockDOMContextProvider(context: context)
        let mockPaste = MockPasteManagerForCopy()

        let execContext = CommandExecutionContext(
            pasteManager: mockPaste,
            clipboardManager: mockClipboard,
            domContextProvider: mockDOMProvider
        )

        // Copy the first heading
        let cmd1 = CopyElementCommand(rawTranscript: "copy the first heading", normalizedTranscript: "copy the first heading", targetType: .heading, targetIndex: 1)
        let result1 = try await cmd1.execute(context: execContext)
        XCTAssertTrue(result1.success)
        XCTAssertEqual(mockClipboard.getString(), "Heading One")

        // Copy the second heading
        let cmd2 = CopyElementCommand(rawTranscript: "copy heading 2", normalizedTranscript: "copy heading 2", targetType: .heading, targetIndex: 2)
        let result2 = try await cmd2.execute(context: execContext)
        XCTAssertTrue(result2.success)
        XCTAssertEqual(mockClipboard.getString(), "Heading Two")
    }

    func testCopyHeadingOutOfRange() async throws {
        let h1 = VisibleElement(id: "h-1", type: .heading, text: "Heading One", bounds: ElementBounds(x: 50, y: 50, width: 400, height: 40), tag: "h1")
        let h2 = VisibleElement(id: "h-2", type: .heading, text: "Heading Two", bounds: ElementBounds(x: 50, y: 300, width: 400, height: 40), tag: "h2")

        let context = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900),
            elements: [h1, h2]
        )

        let mockClipboard = MockClipboardManager(mockString: "unmodified")
        let mockDOMProvider = MockDOMContextProvider(context: context)
        let mockPaste = MockPasteManagerForCopy()

        let execContext = CommandExecutionContext(
            pasteManager: mockPaste,
            clipboardManager: mockClipboard,
            domContextProvider: mockDOMProvider
        )

        let command = CopyElementCommand(rawTranscript: "copy heading 3", normalizedTranscript: "copy heading 3", targetType: .heading, targetIndex: 3)
        let result = try await command.execute(context: execContext)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, "Only 2 visible headings found.")
        XCTAssertEqual(mockClipboard.getString(), "unmodified")
    }

    // MARK: - Button Tests

    func testCopySingleButtonSuccess() async throws {
        let button = VisibleElement(
            id: "btn-1",
            type: .button,
            text: "Button One",
            bounds: ElementBounds(x: 50, y: 100, width: 120, height: 40),
            tag: "button"
        )
        let context = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900),
            elements: [button]
        )

        let mockClipboard = MockClipboardManager(mockString: nil)
        let mockDOMProvider = MockDOMContextProvider(context: context)
        let mockPaste = MockPasteManagerForCopy()

        let execContext = CommandExecutionContext(
            pasteManager: mockPaste,
            clipboardManager: mockClipboard,
            domContextProvider: mockDOMProvider
        )

        let command = CopyElementCommand(rawTranscript: "copy the button", normalizedTranscript: "copy the button", targetType: .button)
        let result = try await command.execute(context: execContext)

        XCTAssertTrue(result.success)
        XCTAssertEqual(mockClipboard.getString(), "Button One")
        XCTAssertTrue(result.message.contains("Copied button"))
    }

    func testCopyButtonAmbiguityWhenMultipleButtonsExist() async throws {
        let btn1 = VisibleElement(id: "btn-1", type: .button, text: "Button One", bounds: ElementBounds(x: 50, y: 100, width: 120, height: 40), tag: "button")
        let btn2 = VisibleElement(id: "btn-2", type: .button, text: "Button Two", bounds: ElementBounds(x: 180, y: 100, width: 120, height: 40), tag: "button")

        let context = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900),
            elements: [btn1, btn2]
        )

        let mockClipboard = MockClipboardManager(mockString: "unmodified")
        let mockDOMProvider = MockDOMContextProvider(context: context)
        let mockPaste = MockPasteManagerForCopy()

        let execContext = CommandExecutionContext(
            pasteManager: mockPaste,
            clipboardManager: mockClipboard,
            domContextProvider: mockDOMProvider
        )

        let command = CopyElementCommand(rawTranscript: "copy the button", normalizedTranscript: "copy the button", targetType: .button)
        let result = try await command.execute(context: execContext)

        XCTAssertFalse(result.success)
        XCTAssertTrue(result.message.contains("Multiple buttons visible (2)"))
        XCTAssertEqual(mockClipboard.getString(), "unmodified")
    }

    func testCopyIndexedButtons() async throws {
        let btn1 = VisibleElement(id: "btn-1", type: .button, text: "Button One", bounds: ElementBounds(x: 50, y: 100, width: 120, height: 40), tag: "button")
        let btn2 = VisibleElement(id: "btn-2", type: .button, text: "Button Two", bounds: ElementBounds(x: 180, y: 100, width: 120, height: 40), tag: "button")

        let context = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900),
            elements: [btn1, btn2]
        )

        let mockClipboard = MockClipboardManager(mockString: nil)
        let mockDOMProvider = MockDOMContextProvider(context: context)
        let mockPaste = MockPasteManagerForCopy()

        let execContext = CommandExecutionContext(
            pasteManager: mockPaste,
            clipboardManager: mockClipboard,
            domContextProvider: mockDOMProvider
        )

        // Copy the first button
        let cmd1 = CopyElementCommand(rawTranscript: "copy the first button", normalizedTranscript: "copy the first button", targetType: .button, targetIndex: 1)
        let res1 = try await cmd1.execute(context: execContext)
        XCTAssertTrue(res1.success)
        XCTAssertEqual(mockClipboard.getString(), "Button One")

        // Copy the second button
        let cmd2 = CopyElementCommand(rawTranscript: "copy button 2", normalizedTranscript: "copy button 2", targetType: .button, targetIndex: 2)
        let res2 = try await cmd2.execute(context: execContext)
        XCTAssertTrue(res2.success)
        XCTAssertEqual(mockClipboard.getString(), "Button Two")
    }

    func testCopyButtonOutOfRange() async throws {
        let btn1 = VisibleElement(id: "btn-1", type: .button, text: "Button One", bounds: ElementBounds(x: 50, y: 100, width: 120, height: 40), tag: "button")

        let context = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900),
            elements: [btn1]
        )

        let mockClipboard = MockClipboardManager(mockString: "unmodified")
        let mockDOMProvider = MockDOMContextProvider(context: context)
        let mockPaste = MockPasteManagerForCopy()

        let execContext = CommandExecutionContext(
            pasteManager: mockPaste,
            clipboardManager: mockClipboard,
            domContextProvider: mockDOMProvider
        )

        let command = CopyElementCommand(rawTranscript: "copy the second button", normalizedTranscript: "copy the second button", targetType: .button, targetIndex: 2)
        let result = try await command.execute(context: execContext)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, "Only 1 visible button found.")
        XCTAssertEqual(mockClipboard.getString(), "unmodified")
    }

    // MARK: - Link Tests

    func testCopySingleLinkSuccess() async throws {
        let link = VisibleElement(
            id: "l-1",
            type: .link,
            text: "Link One",
            bounds: ElementBounds(x: 50, y: 200, width: 100, height: 30),
            tag: "a"
        )
        let context = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900),
            elements: [link]
        )

        let mockClipboard = MockClipboardManager(mockString: nil)
        let mockDOMProvider = MockDOMContextProvider(context: context)
        let mockPaste = MockPasteManagerForCopy()

        let execContext = CommandExecutionContext(
            pasteManager: mockPaste,
            clipboardManager: mockClipboard,
            domContextProvider: mockDOMProvider
        )

        let command = CopyElementCommand(rawTranscript: "copy the link", normalizedTranscript: "copy the link", targetType: .link)
        let result = try await command.execute(context: execContext)

        XCTAssertTrue(result.success)
        XCTAssertEqual(mockClipboard.getString(), "Link One")
        XCTAssertTrue(result.message.contains("Copied link"))
    }

    func testCopyLinkAmbiguityWhenMultipleLinksExist() async throws {
        let l1 = VisibleElement(id: "l-1", type: .link, text: "Link One", bounds: ElementBounds(x: 50, y: 200, width: 100, height: 30), tag: "a")
        let l2 = VisibleElement(id: "l-2", type: .link, text: "Link Two", bounds: ElementBounds(x: 160, y: 200, width: 100, height: 30), tag: "a")
        let l3 = VisibleElement(id: "l-3", type: .link, text: "Link Three", bounds: ElementBounds(x: 270, y: 200, width: 100, height: 30), tag: "a")

        let context = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900),
            elements: [l1, l2, l3]
        )

        let mockClipboard = MockClipboardManager(mockString: "unmodified")
        let mockDOMProvider = MockDOMContextProvider(context: context)
        let mockPaste = MockPasteManagerForCopy()

        let execContext = CommandExecutionContext(
            pasteManager: mockPaste,
            clipboardManager: mockClipboard,
            domContextProvider: mockDOMProvider
        )

        let command = CopyElementCommand(rawTranscript: "copy the link", normalizedTranscript: "copy the link", targetType: .link)
        let result = try await command.execute(context: execContext)

        XCTAssertFalse(result.success)
        XCTAssertTrue(result.message.contains("Multiple links visible (3)"))
        XCTAssertEqual(mockClipboard.getString(), "unmodified")
    }

    func testCopyIndexedLinksAcrossThreeLinks() async throws {
        let l1 = VisibleElement(id: "l-1", type: .link, text: "Link One", bounds: ElementBounds(x: 50, y: 200, width: 100, height: 30), tag: "a")
        let l2 = VisibleElement(id: "l-2", type: .link, text: "Link Two", bounds: ElementBounds(x: 160, y: 200, width: 100, height: 30), tag: "a")
        let l3 = VisibleElement(id: "l-3", type: .link, text: "Link Three", bounds: ElementBounds(x: 270, y: 200, width: 100, height: 30), tag: "a")

        let context = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900),
            elements: [l3, l1, l2] // Scrambled order
        )

        let mockClipboard = MockClipboardManager(mockString: nil)
        let mockDOMProvider = MockDOMContextProvider(context: context)
        let mockPaste = MockPasteManagerForCopy()

        let execContext = CommandExecutionContext(
            pasteManager: mockPaste,
            clipboardManager: mockClipboard,
            domContextProvider: mockDOMProvider
        )

        // 1. Copy the third link
        let cmd3 = CopyElementCommand(rawTranscript: "copy the third link", normalizedTranscript: "copy the third link", targetType: .link, targetIndex: 3)
        let res3 = try await cmd3.execute(context: execContext)
        XCTAssertTrue(res3.success)
        XCTAssertEqual(mockClipboard.getString(), "Link Three")

        // 2. Copy the first link
        let cmd1 = CopyElementCommand(rawTranscript: "copy the first link", normalizedTranscript: "copy the first link", targetType: .link, targetIndex: 1)
        let res1 = try await cmd1.execute(context: execContext)
        XCTAssertTrue(res1.success)
        XCTAssertEqual(mockClipboard.getString(), "Link One")

        // 3. Copy link 2
        let cmd2 = CopyElementCommand(rawTranscript: "copy link 2", normalizedTranscript: "copy link 2", targetType: .link, targetIndex: 2)
        let res2 = try await cmd2.execute(context: execContext)
        XCTAssertTrue(res2.success)
        XCTAssertEqual(mockClipboard.getString(), "Link Two")
    }

    func testCopyLinkOutOfRange() async throws {
        let l1 = VisibleElement(id: "l-1", type: .link, text: "Link One", bounds: ElementBounds(x: 50, y: 200, width: 100, height: 30), tag: "a")
        let l2 = VisibleElement(id: "l-2", type: .link, text: "Link Two", bounds: ElementBounds(x: 160, y: 200, width: 100, height: 30), tag: "a")
        let l3 = VisibleElement(id: "l-3", type: .link, text: "Link Three", bounds: ElementBounds(x: 270, y: 200, width: 100, height: 30), tag: "a")

        let context = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1440, height: 900),
            elements: [l1, l2, l3]
        )

        let mockClipboard = MockClipboardManager(mockString: "unmodified")
        let mockDOMProvider = MockDOMContextProvider(context: context)
        let mockPaste = MockPasteManagerForCopy()

        let execContext = CommandExecutionContext(
            pasteManager: mockPaste,
            clipboardManager: mockClipboard,
            domContextProvider: mockDOMProvider
        )

        let command = CopyElementCommand(rawTranscript: "copy link 4", normalizedTranscript: "copy link 4", targetType: .link, targetIndex: 4)
        let result = try await command.execute(context: execContext)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, "Only 3 visible links found.")
        XCTAssertEqual(mockClipboard.getString(), "unmodified")
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

        let command = CopyElementCommand(rawTranscript: "copy the paragraph", normalizedTranscript: "copy the paragraph", targetType: .paragraph)
        let result = try await command.execute(context: execContext)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, "No visible browser content available")
    }
}
