import XCTest
@testable import ScreenSenseCore

final class MockPasteManagerForPointerTest: PasteManagerProtocol, @unchecked Sendable {
    func executePaste() throws {}
}

final class MockUnifiedContextManagerForPointerTest: UnifiedContextManagerProtocol, @unchecked Sendable {
    private var context: UnifiedContext

    var latestContext: UnifiedContext? { context }
    var currentApplicationName: String { context.applicationName }
    var contextStatusDescription: String { "Ready" }
    var activeTabTitle: String { context.activeTabTitle }
    var isReady: Bool { true }
    var fallbackReason: String? { nil }
    var isBridgeConnected: Bool { true }
    var onContextUpdated: (@Sendable (UnifiedContext) -> Void)? = nil

    init(initialContext: UnifiedContext) {
        self.context = initialContext
    }

    func getUnifiedContext() async -> UnifiedContext {
        return context
    }

    func refreshContext() async -> UnifiedContext {
        return context
    }

    func startMonitoring() {}
    func stopMonitoring() {}
}

final class PointerAndSelectionContextTests: XCTestCase {
    private var parser: GenericIntentParser!
    private var resolver: ContextTargetResolver!
    private var clipboard: MockClipboardManager!
    private var paste: MockPasteManagerForPointerTest!

    override func setUp() {
        super.setUp()
        parser = GenericIntentParser()
        resolver = ContextTargetResolver()
        clipboard = MockClipboardManager()
        paste = MockPasteManagerForPointerTest()
    }

    // MARK: - 1. Parser Tests for Pointer & Selection Intents

    func testParserPointerIntents() {
        let textUnder = parser.parse(transcript: "copy the text under my cursor")
        guard case .copy(let intent1) = textUnder, case .pointerContext(let rel1, let scope1) = intent1.target else {
            XCTFail("Failed parsing 'copy the text under my cursor'")
            return
        }
        XCTAssertEqual(rel1, .under)
        XCTAssertEqual(scope1, .text)

        let paraUnder = parser.parse(transcript: "copy the paragraph under my cursor")
        guard case .copy(let intent2) = paraUnder, case .pointerContext(let rel2, let scope2) = intent2.target else {
            XCTFail("Failed parsing 'copy the paragraph under my cursor'")
            return
        }
        XCTAssertEqual(rel2, .under)
        XCTAssertEqual(scope2, .paragraph)

        let headingUnder = parser.parse(transcript: "copy the heading under my cursor")
        guard case .copy(let intentH) = headingUnder, case .pointerContext(let relH, let scopeH) = intentH.target else {
            XCTFail("Failed parsing 'copy the heading under my cursor'")
            return
        }
        XCTAssertEqual(relH, .under)
        XCTAssertEqual(scopeH, .heading)

        let textAbove = parser.parse(transcript: "copy the text above my cursor")
        guard case .copy(let intent3) = textAbove, case .pointerContext(let rel3, let scope3) = intent3.target else {
            XCTFail("Failed parsing 'copy the text above my cursor'")
            return
        }
        XCTAssertEqual(rel3, .above)
        XCTAssertEqual(scope3, .text)

        let textBelow = parser.parse(transcript: "copy the text below my cursor")
        guard case .copy(let intent4) = textBelow, case .pointerContext(let rel4, let scope4) = intent4.target else {
            XCTFail("Failed parsing 'copy the text below my cursor'")
            return
        }
        XCTAssertEqual(rel4, .below)
        XCTAssertEqual(scope4, .text)

        let textNextTo = parser.parse(transcript: "copy the text next to my cursor")
        guard case .copy(let intent5) = textNextTo, case .pointerContext(let rel5, let scope5) = intent5.target else {
            XCTFail("Failed parsing 'copy the text next to my cursor'")
            return
        }
        XCTAssertEqual(rel5, .nextTo)
        XCTAssertEqual(scope5, .text)

        let pointingAt = parser.parse(transcript: "copy what I'm pointing at")
        guard case .copy(let intent6) = pointingAt, case .pointerContext(let rel6, _) = intent6.target else {
            XCTFail("Failed parsing 'copy what I'm pointing at'")
            return
        }
        XCTAssertEqual(rel6, .under)

        let pointingTo = parser.parse(transcript: "copy the text I'm pointing to")
        guard case .copy(let intent7) = pointingTo, case .pointerContext(let rel7, let scope7) = intent7.target else {
            XCTFail("Failed parsing 'copy the text I'm pointing to'")
            return
        }
        XCTAssertEqual(rel7, .under)
        XCTAssertEqual(scope7, .text)
    }

    func testParserSelectionIntents() {
        let selExact = parser.parse(transcript: "copy the selected text")
        guard case .copy(let intent1) = selExact, case .selection(let scope1) = intent1.target else {
            XCTFail("Failed parsing 'copy the selected text'")
            return
        }
        XCTAssertEqual(scope1, .exact)

        let mySel = parser.parse(transcript: "copy my selection")
        guard case .copy(let intent2) = mySel, case .selection(let scope2) = intent2.target else {
            XCTFail("Failed parsing 'copy my selection'")
            return
        }
        XCTAssertEqual(scope2, .exact)

        let paraSel = parser.parse(transcript: "copy the paragraph I selected")
        guard case .copy(let intent3) = paraSel, case .selection(let scope3) = intent3.target else {
            XCTFail("Failed parsing 'copy the paragraph I selected'")
            return
        }
        XCTAssertEqual(scope3, .paragraph)

        let sentSel = parser.parse(transcript: "copy the sentence I selected")
        guard case .copy(let intent4) = sentSel, case .selection(let scope4) = intent4.target else {
            XCTFail("Failed parsing 'copy the sentence I selected'")
            return
        }
        XCTAssertEqual(scope4, .sentence)

        let textSel = parser.parse(transcript: "copy the text I selected")
        guard case .copy(let intent5) = textSel, case .selection(let scope5) = intent5.target else {
            XCTFail("Failed parsing 'copy the text I selected'")
            return
        }
        XCTAssertEqual(scope5, .textRegion)
    }

    // MARK: - 2. Resolver Tests for Pointer Context

    func testPointerUnderCursorResolvesContainingParagraph() {
        let p1 = VisibleElement(
            id: "p1",
            type: .paragraph,
            text: "Quantum computing is a rapidly-emerging technology that harnesses the laws of quantum mechanics.",
            bounds: ElementBounds(x: 100, y: 150, width: 700, height: 80),
            tag: "p"
        )
        let linkInside = VisibleElement(
            id: "l1",
            type: .link,
            text: "quantum mechanics",
            bounds: ElementBounds(x: 450, y: 180, width: 120, height: 20),
            tag: "a"
        )
        let p2 = VisibleElement(
            id: "p2",
            type: .paragraph,
            text: "The basic unit of information in quantum computing is the qubit.",
            bounds: ElementBounds(x: 100, y: 260, width: 700, height: 60),
            tag: "p"
        )

        // Cursor is over the link inside paragraph 1 (x: 480, y: 190)
        let context = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            elements: [p1, linkInside, p2],
            pointer: PointerContext(x: 480, y: 190)
        )

        // 1. "copy the paragraph under my cursor" -> full paragraph 1
        let paraRes = resolver.resolve(target: .pointerContext(relation: .under, scope: .paragraph), in: context)
        guard case .success(_, let text1) = paraRes else {
            XCTFail("Failed resolving paragraph under cursor")
            return
        }
        XCTAssertEqual(text1, "Quantum computing is a rapidly-emerging technology that harnesses the laws of quantum mechanics.")

        // 2. "copy the text under my cursor" -> containing paragraph text
        let textRes = resolver.resolve(target: .pointerContext(relation: .under, scope: .text), in: context)
        guard case .success(_, let text2) = textRes else {
            XCTFail("Failed resolving text under cursor")
            return
        }
        XCTAssertEqual(text2, "Quantum computing is a rapidly-emerging technology that harnesses the laws of quantum mechanics.")
    }

    func testPointerSpatialAboveAndBelow() {
        let blockAbove = VisibleElement(
            id: "block-above",
            type: .paragraph,
            text: "First section explaining quantum circuits and logical qubits.",
            bounds: ElementBounds(x: 100, y: 100, width: 700, height: 60),
            tag: "p"
        )
        let blockBelow = VisibleElement(
            id: "block-below",
            type: .paragraph,
            text: "Second section detailing experimental implementations and error correction.",
            bounds: ElementBounds(x: 100, y: 300, width: 700, height: 60),
            tag: "p"
        )

        // Cursor positioned in the gap between the two blocks at y: 220
        let context = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            elements: [blockAbove, blockBelow],
            pointer: PointerContext(x: 200, y: 220)
        )

        // 1. "copy the text above my cursor"
        let aboveRes = resolver.resolve(target: .pointerContext(relation: .above, scope: .text), in: context)
        guard case .success(_, let textAbove) = aboveRes else {
            XCTFail("Failed resolving text above cursor")
            return
        }
        XCTAssertEqual(textAbove, "First section explaining quantum circuits and logical qubits.")

        // 2. "copy the text below my cursor"
        let belowRes = resolver.resolve(target: .pointerContext(relation: .below, scope: .text), in: context)
        guard case .success(_, let textBelow) = belowRes else {
            XCTFail("Failed resolving text below cursor")
            return
        }
        XCTAssertEqual(textBelow, "Second section detailing experimental implementations and error correction.")
    }

    // MARK: - 3. Resolver Tests for Selection Context

    func testSelectionExactText() {
        let context = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            elements: [],
            selection: SelectionContext(text: "quantum information")
        )

        let result = resolver.resolve(target: .selection(scope: .exact), in: context)
        guard case .success(_, let text) = result else {
            XCTFail("Failed resolving exact selection")
            return
        }
        XCTAssertEqual(text, "quantum information")
    }

    func testSelectionContainingParagraph() {
        let p1 = VisibleElement(
            id: "p1",
            type: .paragraph,
            text: "Classical computers encode information in binary bits. Quantum computers use quantum bits to perform complex calculations.",
            bounds: ElementBounds(x: 100, y: 150, width: 700, height: 60),
            tag: "p"
        )

        let context = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            elements: [p1],
            selection: SelectionContext(
                text: "quantum bits",
                bounds: ElementBounds(x: 250, y: 170, width: 80, height: 20),
                containingElementId: "p1"
            )
        )

        let result = resolver.resolve(target: .selection(scope: .paragraph), in: context)
        guard case .success(_, let text) = result else {
            XCTFail("Failed resolving paragraph of selection")
            return
        }
        XCTAssertEqual(text, "Classical computers encode information in binary bits. Quantum computers use quantum bits to perform complex calculations.")
    }

    func testSelectionContainingSentence() {
        let p1 = VisibleElement(
            id: "p1",
            type: .paragraph,
            text: "Classical computers encode information in binary bits. Quantum computers use quantum bits to perform complex calculations. This enables exponential speedups.",
            bounds: ElementBounds(x: 100, y: 150, width: 700, height: 60),
            tag: "p"
        )

        let context = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            elements: [p1],
            selection: SelectionContext(
                text: "quantum bits",
                containingElementId: "p1"
            )
        )

        let result = resolver.resolve(target: .selection(scope: .sentence), in: context)
        guard case .success(_, let text) = result else {
            XCTFail("Failed resolving sentence of selection")
            return
        }
        XCTAssertEqual(text, "Quantum computers use quantum bits to perform complex calculations.")
    }

    func testNoSelectionReturnsDeterministicError() {
        let context = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            elements: [
                VisibleElement(id: "p1", type: .paragraph, text: "Some random text.", bounds: ElementBounds(x: 0, y: 0, width: 100, height: 20))
            ],
            selection: nil
        )

        let result = resolver.resolve(target: .selection(scope: .exact), in: context)
        guard case .notFound(let reason) = result else {
            XCTFail("Expected notFound error when no selection exists, got \(result)")
            return
        }
        XCTAssertTrue(reason.contains("No text currently selected"))
    }

    // MARK: - 4. End-to-End Command Execution

    func testGenericCopyActionPointerEndToEnd() async throws {
        let p1 = VisibleElement(
            id: "p1",
            type: .paragraph,
            text: "Quantum supremacy represents the milestone where a programmable quantum device solves a problem no classical supercomputer can solve in any feasible amount of time.",
            bounds: ElementBounds(x: 100, y: 100, width: 800, height: 60),
            tag: "p"
        )

        let context = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            elements: [p1],
            pointer: PointerContext(x: 250, y: 120)
        )

        let parsedIntent = parser.parse(transcript: "copy the paragraph under my cursor")
        guard case .copy(let intent) = parsedIntent else {
            XCTFail("Failed parsing copy intent")
            return
        }

        let mockUnifiedManager = MockUnifiedContextManagerForPointerTest(initialContext: context)
        let execContext = CommandExecutionContext(
            pasteManager: paste,
            clipboardManager: clipboard,
            unifiedContextManager: mockUnifiedManager,
            targetResolver: resolver
        )

        let command = GenericCopyAction(intent: intent)
        let result = try await command.execute(context: execContext)

        XCTAssertTrue(result.success)
        XCTAssertEqual(clipboard.getString(), p1.text)
        XCTAssertTrue(result.message.contains("Copied paragraph under cursor"))
    }

    func testGenericCopyActionSelectionEndToEnd() async throws {
        let context = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            elements: [],
            selection: SelectionContext(text: "Google Quantum AI")
        )

        let parsedIntent = parser.parse(transcript: "copy the selected text")
        guard case .copy(let intent) = parsedIntent else {
            XCTFail("Failed parsing copy intent")
            return
        }

        let mockUnifiedManager = MockUnifiedContextManagerForPointerTest(initialContext: context)
        let execContext = CommandExecutionContext(
            pasteManager: paste,
            clipboardManager: clipboard,
            unifiedContextManager: mockUnifiedManager,
            targetResolver: resolver
        )

        let command = GenericCopyAction(intent: intent)
        let result = try await command.execute(context: execContext)

        XCTAssertTrue(result.success)
        XCTAssertEqual(clipboard.getString(), "Google Quantum AI")
        XCTAssertTrue(result.message.contains("Copied selected text"))
    }
}
