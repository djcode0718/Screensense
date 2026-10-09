import XCTest
import Combine
@testable import ScreenSenseCore

final class MockLiveBrowserBridge: BrowserBridgeProtocol, @unchecked Sendable {
    var isConnected: Bool = true
    var latestDOMContext: VisibleContext?
    var onContextReceived: (@Sendable (VisibleContext) -> Void)?

    var stubbedTabResponse: LiveQueryResponse?
    var stubbedPointerResult: LivePointerResult?
    var stubbedSelectionResult: LiveSelectionResult?
    var stubbedDOMResult: VisibleContext?

    var queryActiveTabCallCount = 0
    var queryActivePointerCallCount = 0
    var queryActiveSelectionCallCount = 0
    var queryActiveDOMCallCount = 0

    var shouldTimeout: Bool = false
    var shouldFailWithTabChanged: Bool = false
    var shouldFailWithContentScriptUnavailable: Bool = false

    func start() throws {}
    func stop() {}

    func queryActiveTab(timeout: TimeInterval = 0.5) async throws -> LiveQueryResponse {
        queryActiveTabCallCount += 1
        if shouldTimeout {
            try? await Task.sleep(nanoseconds: 100_000_000)
            throw LiveQueryError.queryTimeout
        }
        if shouldFailWithTabChanged {
            throw LiveQueryError.tabChangedDuringQuery
        }
        return stubbedTabResponse ?? LiveQueryResponse(
            requestId: UUID().uuidString,
            success: true,
            tabId: "101",
            url: "https://en.wikipedia.org/wiki/Quantum_computing",
            pageTitle: "Quantum computing - Wikipedia",
            viewport: ViewportInfo(width: 1280, height: 800, scrollX: 0, scrollY: 150)
        )
    }

    func queryActivePointer(timeout: TimeInterval = 0.5) async throws -> LivePointerResult {
        queryActivePointerCallCount += 1
        if shouldTimeout {
            try? await Task.sleep(nanoseconds: 100_000_000)
            throw LiveQueryError.queryTimeout
        }
        if shouldFailWithContentScriptUnavailable {
            throw LiveQueryError.contentScriptUnavailable
        }
        if let res = stubbedPointerResult {
            return res
        }
        return LivePointerResult(
            status: "OK",
            x: 450,
            y: 320,
            targetElement: LiveTargetElement(id: "p1", tag: "p", text: "Quantum computing is a rapidly-emerging technology.", bounds: ElementBounds(x: 100, y: 300, width: 600, height: 80), type: "paragraph"),
            containingText: "Quantum computing is a rapidly-emerging technology.",
            containingParagraph: "Quantum computing is a rapidly-emerging technology."
        )
    }

    func queryActiveSelection(timeout: TimeInterval = 0.5) async throws -> LiveSelectionResult {
        queryActiveSelectionCallCount += 1
        if shouldTimeout {
            try? await Task.sleep(nanoseconds: 100_000_000)
            throw LiveQueryError.queryTimeout
        }
        if shouldFailWithContentScriptUnavailable {
            throw LiveQueryError.contentScriptUnavailable
        }
        if let res = stubbedSelectionResult {
            return res
        }
        return LiveSelectionResult(
            status: "OK",
            text: "rapidly-emerging technology",
            isCollapsed: false,
            bounds: ElementBounds(x: 200, y: 305, width: 180, height: 20),
            containingElementId: "p1",
            containingText: "Quantum computing is a rapidly-emerging technology.",
            containingSentence: "Quantum computing is a rapidly-emerging technology.",
            containingParagraph: "Quantum computing is a rapidly-emerging technology."
        )
    }

    func queryActiveDOM(timeout: TimeInterval = 1.0) async throws -> VisibleContext {
        queryActiveDOMCallCount += 1
        if shouldTimeout {
            try? await Task.sleep(nanoseconds: 100_000_000)
            throw LiveQueryError.queryTimeout
        }
        if let dom = stubbedDOMResult {
            return dom
        }
        let dom = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1280, height: 800, scrollX: 0, scrollY: 150, pageTitle: "Quantum computing - Wikipedia", url: "https://en.wikipedia.org/wiki/Quantum_computing"),
            elements: [
                VisibleElement(id: "h1", type: .heading, text: "Quantum computing", bounds: ElementBounds(x: 100, y: 120, width: 400, height: 40)),
                VisibleElement(id: "p1", type: .paragraph, text: "Quantum computing is a rapidly-emerging technology.", bounds: ElementBounds(x: 100, y: 180, width: 600, height: 80))
            ]
        )
        return dom
    }
}

final class LiveQueryBridgeTests: XCTestCase {
    private var mockBridge: MockLiveBrowserBridge!
    private var contextManager: UnifiedContextManager!
    private var clipboard: MockClipboardManager!
    private var paste: MockPasteManagerForPointerTest!
    private var resolver: ContextTargetResolver!
    private var parser: GenericIntentParser!

    override func setUp() {
        super.setUp()
        mockBridge = MockLiveBrowserBridge()
        contextManager = UnifiedContextManager(browserBridge: mockBridge)
        contextManager.setCurrentApplication(name: "Google Chrome")
        clipboard = MockClipboardManager()
        paste = MockPasteManagerForPointerTest()
        resolver = ContextTargetResolver()
        parser = GenericIntentParser()
    }

    private func makeExecutionContext() -> CommandExecutionContext {
        CommandExecutionContext(
            pasteManager: paste,
            clipboardManager: clipboard,
            domContextProvider: DOMContextProvider(bridge: mockBridge),
            semanticSelector: SemanticElementSelector(),
            unifiedContextManager: contextManager,
            targetResolver: resolver
        )
    }

    // MARK: - Pointer Tests (1-8)

    func test1_PointerExists_ResolvesDirectly() async throws {
        mockBridge.stubbedPointerResult = LivePointerResult(
            status: "OK",
            x: 350,
            y: 200,
            targetElement: LiveTargetElement(id: "p1", tag: "p", text: "Text under cursor", bounds: ElementBounds(x: 100, y: 180, width: 500, height: 60), type: "paragraph"),
            containingText: "Text under cursor",
            containingParagraph: "Text under cursor"
        )

        let action = GenericCopyAction(intent: CopyIntent(target: .pointerContext(relation: .under, scope: .text), rawTranscript: "copy the text under my cursor", normalizedTranscript: "copy the text under my cursor"))
        let result = try await action.execute(context: makeExecutionContext())

        XCTAssertTrue(result.success)
        XCTAssertEqual(clipboard.getString(), "Text under cursor")
        XCTAssertEqual(mockBridge.queryActivePointerCallCount, 1)
    }

    func test2_PointerMissing_ReportsDeterministicError() async throws {
        mockBridge.stubbedPointerResult = LivePointerResult(status: "POINTER_UNAVAILABLE", x: 0, y: 0)

        let action = GenericCopyAction(intent: CopyIntent(target: .pointerContext(relation: .under, scope: .text), rawTranscript: "copy the text under my cursor", normalizedTranscript: "copy the text under my cursor"))
        let result = try await action.execute(context: makeExecutionContext())

        XCTAssertFalse(result.success)
        XCTAssertTrue(result.message.contains("Pointer position is unavailable") || result.message.contains("No context"))
    }

    func test3_PointerOverParagraph_CopiesFullParagraph() async throws {
        mockBridge.stubbedPointerResult = LivePointerResult(
            status: "OK",
            x: 300,
            y: 400,
            targetElement: LiveTargetElement(id: "p2", tag: "p", text: "Full paragraph content spanning multiple lines.", bounds: ElementBounds(x: 100, y: 380, width: 600, height: 100), type: "paragraph"),
            containingText: "Full paragraph content spanning multiple lines.",
            containingParagraph: "Full paragraph content spanning multiple lines."
        )

        let action = GenericCopyAction(intent: CopyIntent(target: .pointerContext(relation: .under, scope: .paragraph), rawTranscript: "copy the paragraph under my cursor", normalizedTranscript: "copy the paragraph under my cursor"))
        let result = try await action.execute(context: makeExecutionContext())

        XCTAssertTrue(result.success)
        XCTAssertEqual(clipboard.getString(), "Full paragraph content spanning multiple lines.")
    }

    func test4_PointerOverInlineLinkInsideParagraph_CopiesContainingParagraph() async throws {
        mockBridge.stubbedPointerResult = LivePointerResult(
            status: "OK",
            x: 210,
            y: 410,
            targetElement: LiveTargetElement(id: "a1", tag: "a", text: "quantum mechanics", bounds: ElementBounds(x: 200, y: 405, width: 120, height: 20), type: "link"),
            containingText: "Quantum computing exploits principles of quantum mechanics to solve problems.",
            containingParagraph: "Quantum computing exploits principles of quantum mechanics to solve problems."
        )

        let action = GenericCopyAction(intent: CopyIntent(target: .pointerContext(relation: .under, scope: .paragraph), rawTranscript: "copy the paragraph under my cursor", normalizedTranscript: "copy the paragraph under my cursor"))
        let result = try await action.execute(context: makeExecutionContext())

        XCTAssertTrue(result.success)
        XCTAssertEqual(clipboard.getString(), "Quantum computing exploits principles of quantum mechanics to solve problems.")
    }

    func test5_PointerOverButton_CopiesButtonText() async throws {
        mockBridge.stubbedPointerResult = LivePointerResult(
            status: "OK",
            x: 500,
            y: 600,
            targetElement: LiveTargetElement(id: "btn1", tag: "button", text: "Submit Feedback", bounds: ElementBounds(x: 480, y: 590, width: 140, height: 40), type: "button"),
            containingText: "Submit Feedback",
            containingParagraph: "Submit Feedback"
        )

        let action = GenericCopyAction(intent: CopyIntent(target: .pointerContext(relation: .under, scope: .text), rawTranscript: "copy what I'm pointing at", normalizedTranscript: "copy what i'm pointing at"))
        let result = try await action.execute(context: makeExecutionContext())

        XCTAssertTrue(result.success)
        XCTAssertEqual(clipboard.getString(), "Submit Feedback")
    }

    func test6_PointerAfterScroll_UsesFreshCoordinates() async throws {
        mockBridge.stubbedPointerResult = LivePointerResult(
            status: "OK",
            x: 400,
            y: 250,
            targetElement: LiveTargetElement(id: "p_scrolled", tag: "p", text: "Scrolled paragraph content", bounds: ElementBounds(x: 100, y: 220, width: 600, height: 60), type: "paragraph"),
            containingText: "Scrolled paragraph content",
            containingParagraph: "Scrolled paragraph content"
        )

        let action = GenericCopyAction(intent: CopyIntent(target: .pointerContext(relation: .under, scope: .text), rawTranscript: "copy the text under my cursor", normalizedTranscript: "copy the text under my cursor"))
        let result = try await action.execute(context: makeExecutionContext())

        XCTAssertTrue(result.success)
        XCTAssertEqual(clipboard.getString(), "Scrolled paragraph content")
    }

    func test7_PointerAfterTabSwitch_QueriesNewActiveTab() async throws {
        mockBridge.stubbedPointerResult = LivePointerResult(
            status: "OK",
            x: 300,
            y: 300,
            targetElement: LiveTargetElement(id: "p_turing", tag: "p", text: "Alan Turing was an English mathematician and computer scientist.", bounds: ElementBounds(x: 100, y: 280, width: 600, height: 60), type: "paragraph"),
            containingText: "Alan Turing was an English mathematician and computer scientist.",
            containingParagraph: "Alan Turing was an English mathematician and computer scientist."
        )

        let action = GenericCopyAction(intent: CopyIntent(target: .pointerContext(relation: .under, scope: .paragraph), rawTranscript: "copy the paragraph under my cursor", normalizedTranscript: "copy the paragraph under my cursor"))
        let result = try await action.execute(context: makeExecutionContext())

        XCTAssertTrue(result.success)
        XCTAssertEqual(clipboard.getString(), "Alan Turing was an English mathematician and computer scientist.")
    }

    func test8_PointerQueryReturnsCurrentCoordinates() async throws {
        let result = try await mockBridge.queryActivePointer()
        XCTAssertEqual(result.x, 450)
        XCTAssertEqual(result.y, 320)
    }

    // MARK: - Selection Tests (9-15)

    func test9_ActiveSelection_CopiesExactSelection() async throws {
        mockBridge.stubbedSelectionResult = LiveSelectionResult(
            status: "OK",
            text: "rapidly-emerging technology",
            isCollapsed: false,
            bounds: ElementBounds(x: 200, y: 305, width: 180, height: 20)
        )

        let action = GenericCopyAction(intent: CopyIntent(target: .selection(scope: .exact), rawTranscript: "copy the selected text", normalizedTranscript: "copy the selected text"))
        let result = try await action.execute(context: makeExecutionContext())

        XCTAssertTrue(result.success)
        XCTAssertEqual(clipboard.getString(), "rapidly-emerging technology")
        XCTAssertEqual(mockBridge.queryActiveSelectionCallCount, 1)
    }

    func test10_NoSelection_DeterministicError() async throws {
        mockBridge.stubbedSelectionResult = LiveSelectionResult(status: "NO_ACTIVE_SELECTION", text: "", isCollapsed: true)

        let action = GenericCopyAction(intent: CopyIntent(target: .selection(scope: .exact), rawTranscript: "copy the selected text", normalizedTranscript: "copy the selected text"))
        let result = try await action.execute(context: makeExecutionContext())

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, "No text currently selected in the active Chrome tab.")
    }

    func test11_SelectionAfterPageScroll_CopiesFreshSelection() async throws {
        mockBridge.stubbedSelectionResult = LiveSelectionResult(
            status: "OK",
            text: "algorithms running on quantum circuits",
            isCollapsed: false,
            bounds: ElementBounds(x: 150, y: 450, width: 250, height: 20)
        )

        let action = GenericCopyAction(intent: CopyIntent(target: .selection(scope: .exact), rawTranscript: "copy the selected text", normalizedTranscript: "copy the selected text"))
        let result = try await action.execute(context: makeExecutionContext())

        XCTAssertTrue(result.success)
        XCTAssertEqual(clipboard.getString(), "algorithms running on quantum circuits")
    }

    func test12_SelectionAfterMouseSelection_Authoritative() async throws {
        mockBridge.stubbedSelectionResult = LiveSelectionResult(
            status: "OK",
            text: "superposition and entanglement",
            isCollapsed: false
        )

        let action = GenericCopyAction(intent: CopyIntent(target: .selection(scope: .exact), rawTranscript: "copy my selection", normalizedTranscript: "copy my selection"))
        let result = try await action.execute(context: makeExecutionContext())

        XCTAssertTrue(result.success)
        XCTAssertEqual(clipboard.getString(), "superposition and entanglement")
    }

    func test13_SelectionAfterKeyboardSelection_Authoritative() async throws {
        mockBridge.stubbedSelectionResult = LiveSelectionResult(
            status: "OK",
            text: "polynomial time",
            isCollapsed: false
        )

        let action = GenericCopyAction(intent: CopyIntent(target: .selection(scope: .exact), rawTranscript: "copy the selected text", normalizedTranscript: "copy the selected text"))
        let result = try await action.execute(context: makeExecutionContext())

        XCTAssertTrue(result.success)
        XCTAssertEqual(clipboard.getString(), "polynomial time")
    }

    func test14_SelectedSentence_CopiesFullContainingSentence() async throws {
        mockBridge.stubbedSelectionResult = LiveSelectionResult(
            status: "OK",
            text: "quantum speedup",
            isCollapsed: false,
            containingSentence: "Quantum algorithms provide exponential quantum speedup for factoring integers.",
            containingParagraph: "Full paragraph here."
        )

        let action = GenericCopyAction(intent: CopyIntent(target: .selection(scope: .sentence), rawTranscript: "copy the sentence I selected", normalizedTranscript: "copy the sentence i selected"))
        let result = try await action.execute(context: makeExecutionContext())

        XCTAssertTrue(result.success)
        XCTAssertEqual(clipboard.getString(), "Quantum algorithms provide exponential quantum speedup for factoring integers.")
    }

    func test15_SelectedParagraph_CopiesFullContainingParagraph() async throws {
        mockBridge.stubbedSelectionResult = LiveSelectionResult(
            status: "OK",
            text: "exponential speedup",
            isCollapsed: false,
            containingSentence: "Quantum algorithms provide exponential speedup.",
            containingParagraph: "Quantum computing is a rapidly-emerging technology. Quantum algorithms provide exponential speedup."
        )

        let action = GenericCopyAction(intent: CopyIntent(target: .selection(scope: .paragraph), rawTranscript: "copy the paragraph I selected", normalizedTranscript: "copy the paragraph i selected"))
        let result = try await action.execute(context: makeExecutionContext())

        XCTAssertTrue(result.success)
        XCTAssertEqual(clipboard.getString(), "Quantum computing is a rapidly-emerging technology. Quantum algorithms provide exponential speedup.")
    }

    // MARK: - Active Tab Tests (16-18)

    func test16_QueryCurrentTab() async throws {
        let tabResp = try await mockBridge.queryActiveTab()
        XCTAssertTrue(tabResp.success)
        XCTAssertEqual(tabResp.tabId, "101")
        XCTAssertEqual(tabResp.pageTitle, "Quantum computing - Wikipedia")
    }

    func test17_TabSwitchImmediatelyBeforeQuery() async throws {
        mockBridge.stubbedTabResponse = LiveQueryResponse(
            requestId: "req-tab-2",
            success: true,
            tabId: "102",
            url: "https://en.wikipedia.org/wiki/Alan_Turing",
            pageTitle: "Alan Turing - Wikipedia"
        )
        let tabResp = try await mockBridge.queryActiveTab()
        XCTAssertEqual(tabResp.tabId, "102")
        XCTAssertEqual(tabResp.pageTitle, "Alan Turing - Wikipedia")
    }

    func test18_StaleTabResponseRejection() async throws {
        mockBridge.shouldFailWithTabChanged = true
        do {
            _ = try await mockBridge.queryActiveTab()
            XCTFail("Should have thrown tabChangedDuringQuery")
        } catch let err as LiveQueryError {
            XCTAssertEqual(err, .tabChangedDuringQuery)
        }
    }

    // MARK: - Failure Handling Tests (23-25)

    func test23_ContentScriptUnavailable() async throws {
        mockBridge.shouldFailWithContentScriptUnavailable = true
        let action = GenericCopyAction(intent: CopyIntent(target: .pointerContext(relation: .under, scope: .text), rawTranscript: "copy the text under my cursor", normalizedTranscript: "copy the text under my cursor"))
        let result = try await action.execute(context: makeExecutionContext())
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.message.contains("content script is not loaded"))
    }

    func test24_QueryTimeout() async throws {
        mockBridge.shouldTimeout = true
        let action = GenericCopyAction(intent: CopyIntent(target: .pointerContext(relation: .under, scope: .text), rawTranscript: "copy the text under my cursor", normalizedTranscript: "copy the text under my cursor"))
        let result = try await action.execute(context: makeExecutionContext())
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.message.contains("timed out"))
    }

    func test25_TabChangedDuringQuery() async throws {
        mockBridge.shouldFailWithTabChanged = true
        do {
            _ = try await mockBridge.queryActiveTab()
            XCTFail("Expected tabChangedDuringQuery error")
        } catch let err as LiveQueryError {
            XCTAssertEqual(err, .tabChangedDuringQuery)
        }
    }

    func test26_LiveQueryResponseContinuationMatching() throws {
        let reqId = "test-req-matching-uuid"
        let jsonStr = """
        {
            "requestId": "\(reqId)",
            "success": true,
            "status": "OK",
            "tabId": "42",
            "url": "https://en.wikipedia.org/wiki/Quantum_computing",
            "pageTitle": "Quantum computing - Wikipedia",
            "pointerResult": {
                "status": "OK",
                "x": 250.0,
                "y": 180.0,
                "containingText": "Quantum computing text under cursor"
            },
            "timestamp": "2026-10-09T16:00:00Z"
        }
        """
        let data = jsonStr.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let resp = try decoder.decode(LiveQueryResponse.self, from: data)

        XCTAssertEqual(resp.requestId, reqId)
        XCTAssertEqual(resp.status, "OK")
        XCTAssertEqual(resp.pointerResult?.containingText, "Quantum computing text under cursor")
    }

    func test27_ContentScriptUnavailableDirectlySurfaced() async throws {
        mockBridge.stubbedPointerResult = nil
        mockBridge.shouldFailWithContentScriptUnavailable = true

        let action = GenericCopyAction(intent: CopyIntent(
            target: .pointerContext(relation: .under, scope: .text),
            rawTranscript: "copy the text under my cursor",
            normalizedTranscript: "copy the text under my cursor"
        ))
        let result = try await action.execute(context: makeExecutionContext())

        XCTAssertFalse(result.success)
        XCTAssertTrue(result.message.contains("content script is not loaded"))
    }

    func test28_PointerQueryDoesNotFallBackToStaleUnifiedContextOnFailure() async throws {
        // Set stale context in contextManager
        let staleDOM = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1280, height: 800, scrollX: 0, scrollY: 0),
            elements: [
                VisibleElement(id: "stale-1", type: .paragraph, text: "Old Stale Paragraph", bounds: ElementBounds(x: 10, y: 10, width: 200, height: 50))
            ]
        )
        mockBridge.onContextReceived?(staleDOM)

        // Make live query fail
        mockBridge.shouldTimeout = true

        let action = GenericCopyAction(intent: CopyIntent(
            target: .pointerContext(relation: .under, scope: .paragraph),
            rawTranscript: "copy the paragraph under my cursor",
            normalizedTranscript: "copy the paragraph under my cursor"
        ))

        let result = try await action.execute(context: makeExecutionContext())

        // MUST NOT silently copy "Old Stale Paragraph"
        XCTAssertFalse(result.success)
        XCTAssertNotEqual(clipboard.getString(), "Old Stale Paragraph")
        XCTAssertTrue(result.message.contains("timed out"))
    }
}

