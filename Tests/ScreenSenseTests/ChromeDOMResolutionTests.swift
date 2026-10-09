import XCTest
@testable import ScreenSenseCore

// MARK: - Mocks for Testing Resolution Logic

final class MockBrowserBridge: BrowserBridgeProtocol, @unchecked Sendable {
    var _latestDOM: VisibleContext?
    var _isConnected: Bool = false
    var onContextReceived: (@Sendable (VisibleContext) -> Void)?

    var latestDOMContext: VisibleContext? { _latestDOM }
    var isConnected: Bool { _isConnected }

    func start() throws {}
    func stop() {}

    var stubbedPointerResult: LivePointerResult?
    var stubbedSelectionResult: LiveSelectionResult?
    var stubbedTabResponse: LiveQueryResponse?

    func queryActiveTab(timeout: TimeInterval) async throws -> LiveQueryResponse {
        stubbedTabResponse ?? LiveQueryResponse(requestId: "mock", success: true, tabId: "1", url: "https://example.com", pageTitle: "Mock Page")
    }

    func queryActivePointer(timeout: TimeInterval) async throws -> LivePointerResult {
        stubbedPointerResult ?? LivePointerResult(status: "OK", x: 100, y: 100, containingText: "Mock Pointer Text")
    }

    func queryActiveSelection(timeout: TimeInterval) async throws -> LiveSelectionResult {
        stubbedSelectionResult ?? LiveSelectionResult(status: "OK", text: "Mock Selection Text")
    }

    func queryActiveDOM(timeout: TimeInterval) async throws -> VisibleContext {
        guard let dom = _latestDOM else {
            throw LiveQueryError.liveQueryFailed("No DOM")
        }
        return dom
    }

    func simulateContextUpdate(_ context: VisibleContext) {
        self._latestDOM = context
        self._isConnected = true
        onContextReceived?(context)
    }
}

final class MockScreenCaptureContextProvider: ScreenCaptureContextProviderProtocol, @unchecked Sendable {
    var extractCallCount = 0
    var stubbedOCRContext: UnifiedContext?

    func extractContext(for app: NSRunningApplication?) async -> UnifiedContext? {
        extractCallCount += 1
        return stubbedOCRContext
    }
}

// MARK: - Prompt 6.2 Test Suite

final class ChromeDOMResolutionTests: XCTestCase {

    // 1. Chrome DOM available -> DOM selected
    func testChromeDOMAvailableSelectsDOM() async {
        let mockBridge = MockBrowserBridge()
        let mockScreenCapture = MockScreenCaptureContextProvider()

        let domP = VisibleElement(id: "p1", type: .paragraph, text: "DOM Paragraph Text", bounds: ElementBounds(x: 10, y: 10, width: 200, height: 40))
        let domContext = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1920, height: 1080, pageTitle: "Wikipedia - Quantum Computing"),
            elements: [domP]
        )
        mockBridge.simulateContextUpdate(domContext)

        let manager = UnifiedContextManager(
            browserBridge: mockBridge,
            screenCaptureProvider: mockScreenCapture
        )

        let result = await manager.refreshContext()
        XCTAssertEqual(result.source, .dom)
        XCTAssertEqual(result.elements.count, 1)
        XCTAssertEqual(result.elements[0].text, "DOM Paragraph Text")
    }

    // 2. Chrome DOM available -> OCR NOT invoked
    func testChromeDOMAvailableDoesNotInvokeOCR() async {
        let mockBridge = MockBrowserBridge()
        let mockScreenCapture = MockScreenCaptureContextProvider()

        let domHeading = VisibleElement(id: "h1", type: .heading, text: "Article Title", bounds: ElementBounds(x: 10, y: 10, width: 300, height: 50), tag: "h1")
        let domContext = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1920, height: 1080, pageTitle: "Article Title"),
            elements: [domHeading]
        )
        mockBridge.simulateContextUpdate(domContext)

        let manager = UnifiedContextManager(
            browserBridge: mockBridge,
            screenCaptureProvider: mockScreenCapture
        )

        _ = await manager.refreshContext()
        XCTAssertEqual(mockScreenCapture.extractCallCount, 0, "ScreenCapture OCR should NOT be invoked when Chrome DOM is available")
    }

    // 3. Chrome DOM unavailable -> OCR fallback
    func testChromeDOMUnavailableFallsBackToOCR() async {
        let mockBridge = MockBrowserBridge() // no DOM provided
        let mockScreenCapture = MockScreenCaptureContextProvider()

        let ocrEl = VisibleElement(id: "ocr-1", type: .genericText, text: "Fallback OCR Text", bounds: ElementBounds(x: 10, y: 10, width: 100, height: 20), source: .ocr)
        mockScreenCapture.stubbedOCRContext = UnifiedContext(
            source: .ocr,
            applicationName: "Google Chrome",
            elements: [ocrEl],
            largeTextRegions: []
        )

        let manager = UnifiedContextManager(
            browserBridge: mockBridge,
            screenCaptureProvider: mockScreenCapture
        )
        manager.setCurrentApplication(name: "Google Chrome")

        let result = await manager.refreshContext()
        XCTAssertEqual(result.source, .ocr)
        XCTAssertEqual(mockScreenCapture.extractCallCount, 1)
        XCTAssertNotNil(manager.fallbackReason)
    }

    // 4. Stale OCR + fresh DOM -> DOM selected
    func testStaleOCRWithFreshDOMSelectsDOM() async {
        let mockBridge = MockBrowserBridge()
        let mockScreenCapture = MockScreenCaptureContextProvider()

        let manager = UnifiedContextManager(
            browserBridge: mockBridge,
            screenCaptureProvider: mockScreenCapture
        )

        // Incoming fresh DOM via bridge
        let domEl = VisibleElement(id: "dom-p", type: .paragraph, text: "Fresh DOM Paragraph", bounds: ElementBounds(x: 10, y: 50, width: 300, height: 30), tag: "p")
        let domContext = VisibleContext(
            source: .dom,
            timestamp: Date(),
            viewport: ViewportInfo(width: 1920, height: 1080, pageTitle: "Fresh Page"),
            elements: [domEl]
        )
        mockBridge.simulateContextUpdate(domContext)

        let resolved = await manager.getUnifiedContext()
        XCTAssertEqual(resolved.source, .dom)
        XCTAssertEqual(resolved.elements.first?.text, "Fresh DOM Paragraph")
    }

    // 5. Expired OCR + fresh DOM -> DOM selected
    func testExpiredOCRWithFreshDOMSelectsDOM() async {
        let mockBridge = MockBrowserBridge()
        let mockScreenCapture = MockScreenCaptureContextProvider()

        let domEl = VisibleElement(id: "dom-h1", type: .heading, text: "New Article Heading", bounds: ElementBounds(x: 10, y: 10, width: 400, height: 40), tag: "h1")
        let domContext = VisibleContext(
            source: .dom,
            timestamp: Date(),
            viewport: ViewportInfo(width: 1920, height: 1080, pageTitle: "New Article"),
            elements: [domEl]
        )
        mockBridge.simulateContextUpdate(domContext)

        let manager = UnifiedContextManager(
            browserBridge: mockBridge,
            screenCaptureProvider: mockScreenCapture
        )

        let resolved = await manager.getUnifiedContext()
        XCTAssertEqual(resolved.source, .dom)
        XCTAssertEqual(resolved.elements.first?.text, "New Article Heading")
    }

    // 6. Page navigation -> new DOM context
    func testPageNavigationUpdatesDOMContext() async {
        let mockBridge = MockBrowserBridge()
        let manager = UnifiedContextManager(browserBridge: mockBridge)

        // Page 1
        let page1 = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1920, height: 1080, pageTitle: "Page 1 - Home", url: "https://example.com"),
            elements: [VisibleElement(id: "p1", type: .paragraph, text: "Home Content", bounds: ElementBounds(x: 0, y: 0, width: 100, height: 20))]
        )
        mockBridge.simulateContextUpdate(page1)
        XCTAssertEqual(manager.latestContext?.windowInfo?.title, "Page 1 - Home")

        // Page 2 Navigation
        let page2 = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1920, height: 1080, pageTitle: "Page 2 - Documentation", url: "https://example.com/docs"),
            elements: [VisibleElement(id: "p2", type: .paragraph, text: "Documentation Content", bounds: ElementBounds(x: 0, y: 0, width: 100, height: 20))]
        )
        mockBridge.simulateContextUpdate(page2)
        XCTAssertEqual(manager.latestContext?.windowInfo?.title, "Page 2 - Documentation")
        XCTAssertEqual(manager.latestContext?.elements.first?.text, "Documentation Content")
    }

    // 7. Tab switch -> new DOM context
    func testTabSwitchUpdatesDOMContext() async {
        let mockBridge = MockBrowserBridge()
        let manager = UnifiedContextManager(browserBridge: mockBridge)

        // Tab A
        let tabA = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1920, height: 1080, pageTitle: "Tab A - GitHub"),
            elements: [VisibleElement(id: "a1", type: .heading, text: "Repository sj/Screensense", bounds: ElementBounds(x: 10, y: 10, width: 200, height: 30), tag: "h1")]
        )
        mockBridge.simulateContextUpdate(tabA)
        XCTAssertEqual(manager.latestContext?.windowInfo?.title, "Tab A - GitHub")

        // Tab B Switch
        let tabB = VisibleContext(
            source: .dom,
            viewport: ViewportInfo(width: 1920, height: 1080, pageTitle: "Tab B - StackOverflow"),
            elements: [VisibleElement(id: "b1", type: .heading, text: "Swift Concurrency Question", bounds: ElementBounds(x: 10, y: 10, width: 200, height: 30), tag: "h1")]
        )
        mockBridge.simulateContextUpdate(tabB)
        XCTAssertEqual(manager.latestContext?.windowInfo?.title, "Tab B - StackOverflow")
        XCTAssertEqual(manager.latestContext?.elements.first?.text, "Swift Concurrency Question")
    }

    // 8. Title resolution priority (Prompt 6.7: document/page title metadata > windowInfo > visible H1 > first heading)
    func testTitleResolutionPriority() {
        let resolver = ContextTargetResolver()

        // Case A: Page title metadata present (takes top priority)
        let h1El = VisibleElement(id: "h1", type: .heading, text: "Visible H1 Title", bounds: ElementBounds(x: 20, y: 40, width: 300, height: 32), tag: "h1")
        let contextWithH1 = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            windowInfo: WindowInfo(title: "Document Title In Window", appName: "Google Chrome"),
            viewport: ViewportInfo(width: 1920, height: 1080, pageTitle: "Page Title Metadata"),
            elements: [h1El],
            largeTextRegions: []
        )
        let resA = resolver.resolve(target: .semantic(role: "title", topic: nil), in: contextWithH1)
        if case .success(_, let text) = resA {
            XCTAssertEqual(text, "Page Title Metadata")
        } else {
            XCTFail("Expected pageTitle metadata to take priority")
        }

        // Case B: No viewport.pageTitle, but windowInfo title present
        let contextWithoutPageTitle = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            windowInfo: WindowInfo(title: "Window Title", appName: "Google Chrome"),
            viewport: nil,
            elements: [h1El],
            largeTextRegions: []
        )
        let resB = resolver.resolve(target: .semantic(role: "title", topic: nil), in: contextWithoutPageTitle)
        if case .success(_, let text) = resB {
            XCTAssertEqual(text, "Window Title")
        } else {
            XCTFail("Expected windowInfo title to take priority")
        }

        // Case C: Only windowInfo document title present
        let contextWindowOnly = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            windowInfo: WindowInfo(title: "Documentation Hub - Overview", appName: "Google Chrome"),
            viewport: nil,
            elements: [],
            largeTextRegions: []
        )
        let resC = resolver.resolve(target: .semantic(role: "title", topic: nil), in: contextWindowOnly)
        if case .success(_, let text) = resC {
            XCTAssertEqual(text, "Documentation Hub - Overview")
        } else {
            XCTFail("Expected document title from windowInfo when metadata is missing")
        }
    }

    // 9. Paragraph resolution (1st, 3rd, 5th paragraph)
    func testParagraphResolutionDeterministic() {
        let resolver = ContextTargetResolver()

        let p1 = VisibleElement(id: "p1", type: .paragraph, text: "Paragraph One text.", bounds: ElementBounds(x: 20, y: 50, width: 400, height: 30), tag: "p")
        let p2 = VisibleElement(id: "p2", type: .paragraph, text: "Paragraph Two text.", bounds: ElementBounds(x: 20, y: 90, width: 400, height: 30), tag: "p")
        let p3 = VisibleElement(id: "p3", type: .paragraph, text: "Paragraph Three text.", bounds: ElementBounds(x: 20, y: 130, width: 400, height: 30), tag: "p")
        let p4 = VisibleElement(id: "p4", type: .paragraph, text: "Paragraph Four text.", bounds: ElementBounds(x: 20, y: 170, width: 400, height: 30), tag: "p")
        let p5 = VisibleElement(id: "p5", type: .paragraph, text: "Paragraph Five text.", bounds: ElementBounds(x: 20, y: 210, width: 400, height: 30), tag: "p")

        let context = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            elements: [p1, p2, p3, p4, p5],
            largeTextRegions: []
        )

        // 1st paragraph
        let res1 = resolver.resolve(target: .element(type: .paragraph, index: 1), in: context)
        if case .success(_, let text) = res1 {
            XCTAssertEqual(text, "Paragraph One text.")
        } else {
            XCTFail("Failed resolving 1st paragraph")
        }

        // 3rd paragraph
        let res3 = resolver.resolve(target: .element(type: .paragraph, index: 3), in: context)
        if case .success(_, let text) = res3 {
            XCTAssertEqual(text, "Paragraph Three text.")
        } else {
            XCTFail("Failed resolving 3rd paragraph")
        }

        // 5th paragraph
        let res5 = resolver.resolve(target: .element(type: .paragraph, index: 5), in: context)
        if case .success(_, let text) = res5 {
            XCTAssertEqual(text, "Paragraph Five text.")
        } else {
            XCTFail("Failed resolving 5th paragraph")
        }
    }

    // 10. Heading resolution
    func testHeadingResolutionDeterministic() {
        let resolver = ContextTargetResolver()

        let h1 = VisibleElement(id: "h1", type: .heading, text: "Main Section Heading", bounds: ElementBounds(x: 20, y: 20, width: 400, height: 40), tag: "h1")
        let h2 = VisibleElement(id: "h2", type: .heading, text: "Subsection Heading", bounds: ElementBounds(x: 20, y: 100, width: 300, height: 30), tag: "h2")

        let context = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            elements: [h1, h2],
            largeTextRegions: []
        )

        let res1 = resolver.resolve(target: .element(type: .heading, index: 1), in: context)
        if case .success(_, let text) = res1 {
            XCTAssertEqual(text, "Main Section Heading")
        } else {
            XCTFail("Failed resolving 1st heading")
        }

        let res2 = resolver.resolve(target: .element(type: .heading, index: 2), in: context)
        if case .success(_, let text) = res2 {
            XCTAssertEqual(text, "Subsection Heading")
        } else {
            XCTFail("Failed resolving 2nd heading")
        }
    }

    // 11. Link resolution
    func testLinkResolutionDeterministic() {
        let resolver = ContextTargetResolver()

        let l1 = VisibleElement(id: "l1", type: .link, text: "Read Full Paper", bounds: ElementBounds(x: 20, y: 150, width: 120, height: 20), tag: "a")
        let l2 = VisibleElement(id: "l2", type: .link, text: "Download PDF", bounds: ElementBounds(x: 160, y: 150, width: 100, height: 20), tag: "a")

        let context = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            elements: [l1, l2],
            largeTextRegions: []
        )

        let res1 = resolver.resolve(target: .element(type: .link, index: 1), in: context)
        if case .success(_, let text) = res1 {
            XCTAssertEqual(text, "Read Full Paper")
        } else {
            XCTFail("Failed resolving 1st link")
        }

        let res2 = resolver.resolve(target: .element(type: .link, index: 2), in: context)
        if case .success(_, let text) = res2 {
            XCTAssertEqual(text, "Download PDF")
        } else {
            XCTFail("Failed resolving 2nd link")
        }
    }

    // 12. Word range resolution
    func testWordRangeResolution() {
        let resolver = ContextTargetResolver()

        let p = VisibleElement(
            id: "p1",
            type: .paragraph,
            text: "Quantum computing is a rapidly-emerging technology that harnesses the laws of quantum mechanics.",
            bounds: ElementBounds(x: 20, y: 50, width: 500, height: 40),
            tag: "p"
        )
        let context = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            elements: [p],
            largeTextRegions: []
        )

        // "words 1 to 2" -> "Quantum computing"
        let res = resolver.resolve(
            target: .wordRange(scope: .element(type: .paragraph, index: 1), range: WordRange(start: 1, end: 2)),
            in: context
        )
        if case .success(_, let text) = res {
            XCTAssertEqual(text, "Quantum computing")
        } else {
            XCTFail("Failed resolving word range")
        }
    }

    // 13. Text-to-text range resolution
    func testTextToTextRangeResolution() {
        let resolver = ContextTargetResolver()

        let p = VisibleElement(
            id: "p1",
            type: .paragraph,
            text: "Albert Einstein received the 1921 Nobel Prize in Physics for his services to theoretical physics.",
            bounds: ElementBounds(x: 20, y: 50, width: 500, height: 40),
            tag: "p"
        )
        let context = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            elements: [p],
            largeTextRegions: []
        )

        let res = resolver.resolve(
            target: .textRange(scope: nil, range: TextRange(startText: "1921 Nobel Prize", endText: "theoretical physics")),
            in: context
        )
        if case .success(_, let text) = res {
            XCTAssertEqual(text, "1921 Nobel Prize in Physics for his services to theoretical physics")
        } else {
            XCTFail("Failed resolving text range")
        }
    }

    // 14. Real-world page structure test: Wikipedia / Documentation / E-Commerce
    func testRealWorldWebPageStructures() {
        let resolver = ContextTargetResolver()

        // Wikipedia-like structure
        let wikiH1 = VisibleElement(id: "firstHeading", type: .heading, text: "Alan Turing", bounds: ElementBounds(x: 50, y: 50, width: 400, height: 35), tag: "h1")
        let wikiP1 = VisibleElement(id: "p1", type: .paragraph, text: "Alan Mathison Turing was an English mathematician and computer scientist.", bounds: ElementBounds(x: 50, y: 95, width: 600, height: 40), tag: "p")
        let wikiP2 = VisibleElement(id: "p2", type: .paragraph, text: "Turing was highly influential in the development of theoretical computer science.", bounds: ElementBounds(x: 50, y: 145, width: 600, height: 40), tag: "p")

        let wikiContext = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            viewport: ViewportInfo(width: 1920, height: 1080, pageTitle: "Alan Turing - Wikipedia"),
            elements: [wikiH1, wikiP1, wikiP2],
            largeTextRegions: []
        )

        let titleRes = resolver.resolve(target: .semantic(role: "title", topic: nil), in: wikiContext)
        if case .success(_, let text) = titleRes {
            XCTAssertEqual(text, "Alan Turing - Wikipedia")
        } else {
            XCTFail("Failed resolving Wikipedia title")
        }

        let p1Res = resolver.resolve(target: .element(type: .paragraph, index: 1), in: wikiContext)
        if case .success(_, let text) = p1Res {
            XCTAssertEqual(text, "Alan Mathison Turing was an English mathematician and computer scientist.")
        } else {
            XCTFail("Failed resolving Wikipedia 1st paragraph")
        }

        // Ecommerce structure
        let prodH1 = VisibleElement(id: "prod-title", type: .heading, text: "Sony WH-1000XM5 Wireless Headphones", bounds: ElementBounds(x: 50, y: 50, width: 500, height: 30), tag: "h1")
        let priceSpan = VisibleElement(id: "price", type: .genericText, text: "$399.99", bounds: ElementBounds(x: 50, y: 90, width: 100, height: 25), tag: "span")
        let buyBtn = VisibleElement(id: "buy", type: .button, text: "Add to Cart", bounds: ElementBounds(x: 50, y: 125, width: 150, height: 40), tag: "button")

        let ecomContext = UnifiedContext(
            source: .dom,
            applicationName: "Google Chrome",
            viewport: ViewportInfo(width: 1920, height: 1080, pageTitle: "Sony WH-1000XM5 - Amazon"),
            elements: [prodH1, priceSpan, buyBtn],
            largeTextRegions: []
        )

        let priceRes = resolver.resolve(target: .semantic(role: "price", topic: nil), in: ecomContext)
        if case .success(_, let text) = priceRes {
            XCTAssertEqual(text, "$399.99")
        } else {
            XCTFail("Failed resolving Ecommerce price")
        }

        let btnRes = resolver.resolve(target: .element(type: .button, index: 1), in: ecomContext)
        if case .success(_, let text) = btnRes {
            XCTAssertEqual(text, "Add to Cart")
        } else {
            XCTFail("Failed resolving Ecommerce button")
        }
    }
}
